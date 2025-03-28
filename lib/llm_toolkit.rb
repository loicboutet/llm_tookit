# External dependencies
require "faraday"
require "faraday/retry"

# Internal components
require "llm_toolkit/tool_dsl"
require "llm_toolkit/configuration"
require "llm_toolkit/engine"

module LlmToolkit
  # Define a base error class for the gem
  class Error < StandardError; end
  
  mattr_accessor :config
  
  class << self
    def configure
      @@config ||= Configuration.new
      yield @@config
    end
    
    alias configuration config
    
    # Helper method to ensure a conversation exists for a conversable
    def ensure_conversation(conversable, agent_type = :planner)
      conversable.conversations.last || conversable.conversations.create!(agent_type: agent_type)
    end
  end
end