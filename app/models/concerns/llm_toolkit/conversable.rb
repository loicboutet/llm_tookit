module LlmToolkit
  module Conversable
    extend ActiveSupport::Concern
    
    included do
      has_many :conversations, as: :conversable, class_name: 'LlmToolkit::Conversation', dependent: :destroy
    end
    
    # Chat interface - create or continue conversation and send message
    # @param message [String] The message to send to the LLM
    # @param provider [LlmToolkit::LlmProvider, nil] An optional specific provider to use
    # @param tools [Array<Class>, nil] Optional tools to use for this interaction
    # @param new_conversation [Boolean] Whether to create a new conversation or use existing
    # @return [LlmToolkit::Message] The assistant's response message
    def chat(message, provider: nil, tools: nil, new_conversation: false)
      # Get the conversation - create new or find last one
      conversation = if new_conversation
                       conversations.create!(agent_type: :planner) # Use a valid agent_type
                     else
                       conversations.last || conversations.create!(agent_type: :planner)
                     end
      
      # Forward to the conversation's chat method
      conversation.chat(message, provider: provider, tools: tools || self.class.default_tools)
    end
    
    # Default LLM provider implementation - can be overridden by classes
    # @return [LlmToolkit::LlmProvider] The default LLM provider to use
    def default_llm_provider
      provider_method = self.class.get_default_llm_provider_method || :default_llm_provider
      
      if provider_method != :default_llm_provider && respond_to?(provider_method)
        send(provider_method)
      elsif respond_to?(:user) && user.respond_to?(:default_llm_provider)
        user.default_llm_provider
      else
        LlmToolkit::LlmProvider.first
      end
    end
    
    # Default system prompt implementation - can be overridden by classes
    # @param role [Symbol, nil] Optional role for different prompts
    # @return [Array<Hash>] Array of system messages
    def generate_system_messages(role = nil)
      prompt_method = self.class.get_default_system_prompt_method || :generate_system_messages
      
      if prompt_method != :generate_system_messages && respond_to?(prompt_method)
        send(prompt_method, role)
      else
        []
      end
    end
    
    class_methods do
      # Get default LLM provider method
      def get_default_llm_provider_method
        @default_llm_provider_method
      end
      
      # Set default LLM provider method
      # @param method_name [Symbol] The method name to call for getting the provider
      def default_llm_provider_method(method_name)
        @default_llm_provider_method = method_name
      end
      
      # Get default tools
      def default_tools(*tool_classes)
        if tool_classes.empty?
          @default_tools || []
        else
          @default_tools = tool_classes.flatten
        end
      end
      
      # Get default system prompt method
      def get_default_system_prompt_method
        @default_system_prompt_method
      end
      
      # Set default system prompt method
      # @param method_name [Symbol] The method name to call for system prompts
      def default_system_prompt_method(method_name)
        @default_system_prompt_method = method_name
      end
    end
  end
end