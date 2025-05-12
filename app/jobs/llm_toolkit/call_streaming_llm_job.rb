module LlmToolkit
  class CallStreamingLlmJob < ApplicationJob
    queue_as :llm

    # Process streaming LLM requests asynchronously
    #
    # @param conversation_id [Integer] The ID of the conversation to process
    # @param llm_model_id [Integer] The ID of the LLM model to use
    # @param user_id [Integer] ID of the user making the request
    # @param tool_class_names [Array<String>] Names of tool classes to use (default: [])
    # @param broadcast_to [String, nil] Optional channel for broadcasting updates (default: nil)
    def perform(conversation_id, llm_model_id, user_id, tool_class_names = [], broadcast_to = nil)
      # Retrieve the conversation and model
      conversation = LlmToolkit::Conversation.find_by(id: conversation_id)
      llm_model = LlmToolkit::LlmModel.find_by(id: llm_model_id)

      return unless conversation && llm_model

      # Create the initial empty assistant message with associated llm_model
      assistant_message = conversation.messages.create!(
        role: 'assistant', # Default to assistant role
        content: '', # Start empty
        user_id: user_id, # Track who initiated
        llm_model: llm_model # Associate with the LLM model
      )

      # Set up Thread.current[:current_user_id] for tools that need it
      Thread.current[:current_user_id] = user_id

      # Ensure tool_class_names is an array before mapping
      safe_tool_class_names = Array(tool_class_names)
      tool_classes = safe_tool_class_names.map { |class_name| class_name.constantize rescue nil }.compact

      # Create the streaming service, passing the llm_model and the new assistant message
      service = LlmToolkit::CallStreamingLlmWithToolService.new(
        llm_model: llm_model,
        conversation: conversation,
        assistant_message: assistant_message, # Pass the newly created message object
        tool_classes: tool_classes,
        user_id: user_id,
        broadcast_to: broadcast_to # Pass the broadcast channel if provided
      )

      # Process the streaming LLM call
      response = service.call

      # If we have a finish_reason in the response and it's not already set on the message,
      # update the message with the finish_reason
      if response.is_a?(Hash) && response['finish_reason'].present? && assistant_message.finish_reason.blank?
        assistant_message.update(finish_reason: response['finish_reason'])
        Rails.logger.info("Updated message finish_reason from final response: #{response['finish_reason']}")
      end
    rescue => e
      Rails.logger.error("Error in CallStreamingLlmJob: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      
      # Update conversation status to resting on error
      conversation&.update(status: :resting)
      
      # Update the assistant message with error details
      assistant_message&.update(
        content: "Error processing your streaming request: #{e.message}",
        is_error: true
      )
    end
  end
end