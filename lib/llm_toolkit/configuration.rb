module LlmToolkit
  class Configuration
    attr_accessor :dangerous_tools
    attr_accessor :default_anthropic_model
    attr_accessor :default_max_tokens
    attr_accessor :referer_url

    def initialize
      @dangerous_tools = []
      @default_anthropic_model = "claude-3-7-sonnet-20250219"
      @default_max_tokens = 8192
      @referer_url = "http://localhost:3000"
    end
  end
end