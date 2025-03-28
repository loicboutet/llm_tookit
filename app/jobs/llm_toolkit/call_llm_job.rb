module LlmToolkit
  class CallLlmJob < ApplicationJob
    queue_as :llm

    # Process LLM requests asynchronously
    #
    # @param conversation_id [Integer] The ID of the conversation to process
    # @param llm_provider_id [Integer] The ID of the LLM provider to use
    # @param tool_class_names [Array<String>] Names of tool classes to use
    # @param role [Symbol, String] Role to use for conversation history
    # @param user_id [Integer] ID of the user making the request
    def perform(conversation_id, llm_provider_id, tool_class_names = [], role = nil, user_id = nil)
      # Retrieve the conversation and provider
      conversation = LlmToolkit::Conversation.find_by(id: conversation_id)
      llm_provider = LlmToolkit::LlmProvider.find_by(id: llm_provider_id)
      
      return unless conversation && llm_provider
      
      # Set up Thread.current[:current_user_id] for tools that need it
      Thread.current[:current_user_id] = user_id

      # Convert tool class names to actual classes
      tool_classes = tool_class_names.map { |class_name| class_name.constantize rescue nil }.compact
      
      # Create and call the service
      service = LlmToolkit::CallLlmWithToolService.new(
        llm_provider: llm_provider,
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
        user_id: user_id
      )
    end
  end
end