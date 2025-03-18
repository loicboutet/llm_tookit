require "llm_toolkit/version"
require "llm_toolkit/engine"
require "llm_toolkit/configuration"

# Third-party dependencies
begin
  require "http"
rescue LoadError => e
  # We'll attempt to load it again in the engine initializer
end

# Ensure required concerns are loaded first
require_relative "../app/models/concerns/llm_toolkit/cancellation_check"

# Ensure AbstractTool is loaded before ToolDSL
require_relative "../app/services/llm_toolkit/tools/abstract_tool"
require_relative "llm_toolkit/tool_dsl"

module LlmToolkit
  class << self
    def configure
      yield(config)
    end

    def config
      @config ||= Configuration.new
    end
    
    # Helper method to ensure a conversation exists for a conversable object
    # @param conversable [Object] Any object with Conversable concern included
    # @param agent_type [Symbol, nil] Optional agent type to use (defaults to :planner)
    # @return [LlmToolkit::Conversation] The conversation
    def ensure_conversation(conversable, agent_type = nil)
      agent_type ||= :planner
      
      # Make sure agent_type is valid
      unless [:planner, :coder, :reviewer, :tester].include?(agent_type)
        agent_type = :planner
      end
      
      # Try to find an existing conversation
      conversation = conversable.conversations.where(status: [:resting, :waiting]).last
      
      # Create a new one if needed
      if conversation.nil?
        conversation = conversable.conversations.create!(
          agent_type: agent_type,
          status: :resting
        )
      end
      
      conversation
    end
  end
end