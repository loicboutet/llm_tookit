module LlmToolkit
  class CallLlmJob < ApplicationJob
    queue_as :llm

    # Process LLM requests asynchronously
    #
    # @param conversation_id [Integer] The ID of the conversation to process
    # @param llm_model_id [Integer] The ID of the LLM model to use
    # @param tool_class_names [Array<String>] Names of tool classes to use
    # @param role [Symbol, String] Role to use for conversation history
    # @param user_id [Integer] ID of the user making the request
    def perform(conversation_id, llm_model_id, tool_class_names = [], role = nil, user_id = nil)
      # Retrieve the conversation and model
      conversation = LlmToolkit::Conversation.find_by(id: conversation_id)
      llm_model = LlmToolkit::LlmModel.find_by(id: llm_model_id)

      return unless conversation && llm_model

      # Set up Thread.current[:current_user_id] for tools that need it
      Thread.current[:current_user_id] = user_id

      # Convert tool class names to actual classes
      tool_classes = tool_class_names.map { |class_name| class_name.constantize rescue nil }.compact
      
      # Create and call the service (Service needs update to accept llm_model)
      service = LlmToolkit::CallLlmWithToolService.new(
        llm_model: llm_model,
        conversation: conversation,
        tool_classes: tool_classes,
        role: role&.to_sym,
        user_id: user_id
      )
      
      # Process the LLM call
      service.call
    rescue => e
      Rails.logger.error("Error in CallLlmJob: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      
      # Update conversation status to resting on error
      conversation&.update(status: :resting)
      
      # Create an error message
      conversation&.messages&.create!(
        role: 'assistant',
        content: "Error processing your request: #{e.message}",
        is_error: true,
        # llm_model: llm_model, # Removed association
        user_id: user_id
      )
    end
  end
end
