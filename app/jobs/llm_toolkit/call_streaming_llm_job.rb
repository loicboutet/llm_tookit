module LlmToolkit
  class CallStreamingLlmJob < ApplicationJob
    queue_as :llm

    # Process streaming LLM requests asynchronously
    #
    # @param conversation_id [Integer] The ID of the conversation to process
    # @param llm_provider_id [Integer] The ID of the LLM provider to use
    # @param llm_provider_id [Integer] The ID of the LLM provider to use
    # @param assistant_message_id [Integer] The ID of the pre-created empty assistant message
    # @param tool_class_names [Array<String>] Names of tool classes to use
    # @param role [Symbol, String] Role to use for conversation history
    # @param user_id [Integer] ID of the user making the request
    def perform(conversation_id, llm_provider_id, assistant_message_id, tool_class_names = [], role = nil, user_id = nil)
      # Retrieve the conversation and provider
      conversation = LlmToolkit::Conversation.find_by(id: conversation_id)
      llm_provider = LlmToolkit::LlmProvider.find_by(id: llm_provider_id)
      # Find the pre-created assistant message
      assistant_message = LlmToolkit::Message.find_by(id: assistant_message_id)
      # Ensure all necessary records are found
      return unless conversation && llm_provider && assistant_message
      
      # Set up Thread.current[:current_user_id] for tools that need it
      Thread.current[:current_user_id] = user_id

      # Convert tool class names to actual classes
      tool_classes = tool_class_names.map { |class_name| class_name.constantize rescue nil }.compact
      
      # Create the streaming service, passing the assistant message
      service = LlmToolkit::CallStreamingLlmWithToolService.new(
        llm_provider: llm_provider,
        conversation: conversation,
        assistant_message: assistant_message, # Pass the message object
        tool_classes: tool_classes,
        role: role&.to_sym,
        user_id: user_id
      )

      # Process the streaming LLM call
      service.call
    rescue => e
      Rails.logger.error("Error in CallStreamingLlmJob: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      
      # Update conversation status to resting on error
      conversation&.update(status: :resting)
      
      # Update the pre-created message with error details
      assistant_message&.update(
        content: "Error processing your streaming request: #{e.message}",
        is_error: true,
        user_id: user_id
      )
      
      # Note: Error broadcasting via custom channel removed. 
      # Consider adding Turbo Stream error broadcasting if needed.
    end
  end
end
