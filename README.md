# LlmToolkit

A Rails engine for seamless integration of Large Language Models (LLMs) into your Rails application, with a focus on conversational interfaces and tool use capabilities.

## Features

- 🧠 **Conversational Memory**: Persist conversations and messages in your database
- 🛠️ **Tool Framework**: Let AI agents use custom tools to perform actions in your application
- 🔌 **Multiple Providers**: Support for Anthropic and OpenRouter (with more coming soon)
- 🔄 **Extensible**: Add your own tools and integrate with any part of your application
- 💬 **Simple Chat Interface**: Just call `chat` on any conversable object

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'llm_toolkit'
```

Then execute:

```bash
$ bundle install
$ rails generate llm_toolkit:install
$ rails db:migrate
```

## Configuration

Configure LlmToolkit in an initializer that will be created during installation:

```ruby
# config/initializers/llm_toolkit.rb
LlmToolkit.configure do |config|
  # Tools that require user confirmation before execution
  # These tools will be marked as pending and won't execute until approved
  config.dangerous_tools = []
  
  # Default model for Anthropic Claude
  config.default_anthropic_model = "claude-3-sonnet-20240229"
  
  # Default maximum tokens for LLM responses
  config.default_max_tokens = 4096
  
  # Referer URL for OpenRouter API requests
  config.referer_url = "http://localhost:3000"
end
```

## API Keys Setup

To use LlmToolkit, you'll need to obtain API keys from the LLM providers you want to use:

1. **Create LLM Provider records**: Use the `LlmToolkit::LlmProvider` model to store your API keys:

```ruby
# For a user-owned provider
user.llm_providers.create!(
  name: "My Claude",
  provider_type: "anthropic",
  api_key: "sk-ant-your-api-key-here",
  settings: { model: "claude-3-opus-20240229" }
)

# For an application-wide provider
LlmToolkit::LlmProvider.create!(
  name: "App OpenRouter",
  provider_type: "openrouter",
  api_key: "your-openrouter-key",
  owner: YourAppModel.first # Some global owner model
)
```

2. **Security considerations**: Always handle API keys securely:
   - Use Rails credentials or environment variables
   - Never commit API keys to version control
   - Consider using encrypted database columns for the api_key field

## Basic Usage

### 1. Make a model conversable

Add the `Conversable` concern to any model you want to chat with:

```ruby
class Problematic < ApplicationRecord
  include LlmToolkit::Conversable
  
  # Optionally configure defaults
  default_tools LlmToolkit::Tools::SubjectGenerator
  default_system_prompt_method :generate_problematic_system_prompt
  
  # Custom system prompt method
  def generate_system_prompt(role = nil)
    ["You are an expert at understanding problem domains."]
  end
end
```

### 2. Start chatting

The simplest way to interact with an LLM:

```ruby
problematic = Problematic.find(1)
response = problematic.chat("Generate subjects based on this problematic")
```

This will:
1. Find or create a conversation for this problematic
2. Add your message
3. Call the LLM with appropriate context
4. Return the assistant's response message

### 3. Advanced chat options

Specify provider, tools, or create a new conversation:

```ruby
# Use a specific provider
anthropic = current_user.llm_providers.find_by(provider_type: 'anthropic')
problematic.chat("Refine these subjects", provider: anthropic)

# Use specific tools
problematic.chat("List resources for each subject", 
                tools: [LlmToolkit::Tools::ResourceGenerator])

# Start a fresh conversation
problematic.chat("Let's approach this from a different angle", 
                new_conversation: true)
```

### 4. Chat with an existing conversation

You can also chat directly with a conversation object:

```ruby
conversation = problematic.conversations.last
conversation.chat("Can you elaborate on the third subject?")
```

## Customizing Models

### Setting Default Tools

Configure default tools for all instances of a model:

```ruby
class Method < ApplicationRecord
  include LlmToolkit::Conversable
  
  default_tools LlmToolkit::Tools::StepGenerator, 
                LlmToolkit::Tools::ActionGenerator
end
```

### Custom Provider Selection

Override how the LLM provider is selected:

```ruby
class Method < ApplicationRecord
  include LlmToolkit::Conversable
  
  default_llm_provider_method :get_premium_provider
  
  def get_premium_provider
    # Custom logic to select a provider
    user.llm_providers.find_by(name: 'Claude Opus') || 
      user.default_llm_provider
  end
end
```

### Custom System Prompts

Control the system prompts sent to the LLM:

```ruby
class Method < ApplicationRecord
  include LlmToolkit::Conversable
  
  default_system_prompt_method :method_system_prompt
  
  def method_system_prompt(role = nil)
    case role
    when :planner
      ["You are planning steps for a methodology."]
    else
      ["You are helping create a detailed method."]
    end
  end
end
```

## Creating Custom Tools

LlmToolkit provides a Ruby-like DSL for creating tools with minimal boilerplate:

```ruby
class WeatherTool < LlmToolkit::ToolDSL
  description "Gets current weather for a location"
  
  param :city, desc: "The city name"
  param :country, desc: "The country code", required: false
  
  def execute(conversable:, tool_use:, city:, country: nil)
    location = country ? "#{city}, #{country}" : city
    
    # Make API call to weather service
    response = WeatherService.get_weather(location)
    
    {
      result: {
        location: response.location,
        temperature: response.temperature,
        conditions: response.conditions
      }
    }
  rescue => e
    { error: "Weather service error: #{e.message}" }
  end
end
```

For detailed information on creating tools, see the [Tools Guide](TOOLS.md).

## Conversation Management

Conversations and messages are stored in your database:

```ruby
# Get all conversations for a conversable
problematic.conversations

# Get messages from a conversation
conversation.messages

# Check tool uses and results
message.tool_uses
tool_use.tool_result
```

### Helper Methods

Use the included helper method for conversation management:

```ruby
# Ensure a conversation exists or create one
conversation = LlmToolkit.ensure_conversation(problematic)
```

## Architecture

LlmToolkit uses several models to manage conversations:

- `LlmProvider`: Stores credentials and settings for an LLM provider
- `Conversation`: Represents a conversation thread with an LLM
- `Message`: Individual messages within a conversation
- `ToolUse`: When the LLM wants to use a tool
- `ToolResult`: The result of executing a tool

For more detailed architectural information, see the [Architecture Guide](ARCHITECTURE.md).

## License

This project is licensed under the MIT License.