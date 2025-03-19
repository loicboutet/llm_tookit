# LlmToolkit Architecture

This document describes the technical architecture of the LlmToolkit engine, designed to provide Rails applications with seamless integration of Large Language Models.

## Core Concepts

### Conversable Objects

The foundation of LlmToolkit is the `Conversable` concern, which can be included in any ActiveRecord model to make it "conversable" - meaning it can participate in conversations with an LLM. When included, this adds:

- A `has_many` relationship to conversations
- A `chat` method for simple LLM interaction
- Customizable defaults for LLM providers, tools, and system prompts

### Conversations

A conversation represents a chat thread with an LLM. It belongs to a `conversable` object through a polymorphic relationship and contains a series of messages. Key attributes:

- `agent_type`: The role or purpose of this conversation (e.g., planner, coder)
- `status`: Current state of the conversation (resting, working, waiting)
- `messages`: Collection of messages in the conversation

### Messages

Messages represent individual exchanges within a conversation. Each message has:

- `role`: Either 'user' or 'assistant'
- `content`: The text content of the message
- `tool_uses`: Any tools the LLM attempted to use within this message

### Tool Framework

The tool framework allows LLMs to perform actions in your application:

- `ToolUse`: Represents an LLM's attempt to use a tool
- `ToolResult`: Stores the result of executing a tool
- `AbstractTool`: Base class for all tools, defines the interface

## Architectural Components

### 1. Conversable Concern

```ruby
module LlmToolkit::Conversable
  extend ActiveSupport::Concern
  
  included do
    has_many :conversations, as: :conversable
    
    class_attribute :default_llm_provider_method
    class_attribute :default_tools
    class_attribute :default_system_prompt_method
  end
  
  # Chat method
  def chat(message, provider: nil, tools: nil, new_conversation: false)
    # Implementation details
  end
end
```

### 2. Conversation Model

Manages the state of an ongoing conversation with an LLM:

```ruby
module LlmToolkit
  class Conversation < ApplicationRecord
    belongs_to :conversable, polymorphic: true
    has_many :messages
    
    # Chat method
    def chat(message, provider: nil, tools: nil)
      # Implementation details
    end
    
    # Convert conversation history to LLM-specific format
    def history(role = nil, provider_type: nil)
      # Implementation details
    end
  end
end
```

### 3. Message Model

Stores individual messages within a conversation:

```ruby
module LlmToolkit
  class Message < ApplicationRecord
    belongs_to :conversation
    has_many :tool_uses
    
    # Format message for LLM consumption
    def for_llm(role, provider_type)
      # Implementation details
    end
  end
end
```

### 4. LLM Provider Model

Encapsulates credentials and details for an LLM provider:

```ruby
module LlmToolkit
  class LlmProvider < ApplicationRecord
    belongs_to :owner, polymorphic: true
    
    # Call the LLM with messages and tools
    def call(system_messages, conversation_history, tools = nil)
      # Implementation details
    end
  end
end
```

### 5. Tool System

The tool system allows LLMs to perform actions in your application:

```ruby
module LlmToolkit
  module Tools
    class AbstractTool
      # Tool definition (name, description, schema)
      def self.definition
        # Must be implemented by subclasses
      end
      
      # Execute the tool with args
      def self.execute(conversable:, args:, tool_use: nil)
        # Must be implemented by subclasses
      end
    end
  end
end
```

### 6. CallLlmWithToolService

This service orchestrates the process of calling an LLM and handling tool use:

```ruby
module LlmToolkit
  class CallLlmWithToolService
    def initialize(llm_provider:, conversation:, tool_classes: [])
      # Setup
    end
    
    def call
      # Call LLM, process response, handle tools
    end
  end
end
```

## Data Flow

### Basic Chat Flow

1. User calls `chat` on a conversable object
2. The method finds/creates a conversation 
3. A user message is created with the prompt text
4. `CallLlmWithToolService` is initialized with the conversation and tools
5. The service calls the LLM provider with conversation history
6. The response is processed and stored as an assistant message
7. Any tool uses are extracted and processed
8. Tool results are fed back to the LLM if needed
9. The final assistant message is returned

### Tool Execution Flow

1. LLM response contains a tool call
2. Tool call is extracted and a `ToolUse` record is created
3. If the tool is "dangerous", it's marked as pending for approval
4. Otherwise, the tool is executed with the provided arguments
5. Result is stored as a `ToolResult` linked to the `ToolUse`
6. For subsequent LLM calls, tool results are included in the context

## Configuration Options

The LlmToolkit can be configured at three levels:

1. **Global configuration**:
   ```ruby
   LlmToolkit.configure do |config|
     config.dangerous_tools = ['write_to_file']
     config.default_anthropic_model = "claude-3-7-sonnet-20250219"
   end
   ```

2. **Class-level defaults**:
   ```ruby
   class Problematic < ApplicationRecord
     include LlmToolkit::Conversable
     
     default_tools LlmToolkit::Tools::SubjectGenerator
     default_system_prompt_method :generate_prompt
   end
   ```

3. **Instance-level overrides**:
   ```ruby
   problematic.chat("Generate subjects", 
     provider: custom_provider,
     tools: custom_tools
   )
   ```

## Extension Points

### 1. Custom Tools

Create new tools by inheriting from `AbstractTool`:

```ruby
class CustomTool < LlmToolkit::Tools::AbstractTool
  def self.definition
    # Tool definition
  end
  
  def self.execute(conversable:, args:, tool_use: nil)
    # Tool implementation
  end
end
```

### 2. Custom Providers

Support for new LLM providers can be added by extending the `LlmProvider` model.

### 3. Custom System Prompts

Override `generate_system_messages` in your conversable models to provide custom system prompts.

## Helper Methods

### LlmToolkit.ensure_conversation

```ruby
def self.ensure_conversation(conversable, agent_type = nil)
  agent_type ||= conversable.class.name.underscore.to_sym
  
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
```

## Best Practices

1. **Conversable Models**: Only include `Conversable` on models where it makes sense to have conversations.

2. **Tool Safety**: Mark tools as dangerous if they could perform destructive actions.

3. **System Prompts**: Craft clear, specific system prompts for each conversable type.

4. **Conversation Management**: Use `new_conversation: true` when starting a conceptually new conversation.

5. **Error Handling**: LLM calls can fail; wrap in appropriate error handling.

## Database Schema

```
llm_toolkit_llm_providers
  - id: bigint
  - name: string
  - api_key: string (encrypted)
  - provider_type: string
  - settings: jsonb
  - owner_id: bigint
  - owner_type: string

llm_toolkit_conversations
  - id: bigint
  - conversable_id: bigint
  - conversable_type: string
  - agent_type: integer
  - status: string
  - canceled_by_id: bigint
  - canceled_by_type: string

llm_toolkit_messages
  - id: bigint
  - conversation_id: bigint
  - role: string
  - content: text
  - user_id: bigint

llm_toolkit_tool_uses
  - id: bigint
  - message_id: bigint
  - name: string
  - input: jsonb
  - tool_use_id: string
  - status: string

llm_toolkit_tool_results
  - id: bigint
  - tool_use_id: bigint
  - message_id: bigint
  - content: text
  - is_error: boolean
  - diff: text
  - pending: boolean
```