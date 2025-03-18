# LlmToolkit Usage Guide

This guide provides practical examples of how to use LlmToolkit in your Rails application.

## Basic Chat Interaction

The simplest way to chat with an LLM is through a conversable object:

```ruby
# Assuming Problematic includes LlmToolkit::Conversable
problematic = Problematic.find(1)

# Send a message and get a response
response = problematic.chat("Generate 5 potential subjects based on this problematic.")

# Access the response content
puts response.content
# => "Here are 5 potential subjects based on your problematic..."

# Access all messages in the conversation
conversation = problematic.conversations.last
conversation.messages.each do |message|
  puts "#{message.role}: #{message.content}"
end
```

## Advanced Chat Options

### Using a Specific LLM Provider

```ruby
# Get an LLM provider
anthropic = current_user.llm_providers.find_by(provider_type: 'anthropic', name: 'Claude Opus')

# Use it for this specific chat
response = problematic.chat(
  "Suggest methods for addressing these subjects",
  provider: anthropic
)
```

### Using Specific Tools

```ruby
# Chat with specific tools enabled
response = problematic.chat(
  "Create steps for implementing this method",
  tools: [LlmToolkit::Tools::StepGenerator, LlmToolkit::Tools::ActionGenerator]
)

# Check if the LLM used any tools
if response.tool_uses.any?
  response.tool_uses.each do |tool_use|
    puts "Used tool: #{tool_use.name}"
    puts "Tool result: #{tool_use.tool_result&.content}"
  end
end
```

### Starting a New Conversation

```ruby
# Start a fresh conversation instead of continuing the existing one
response = problematic.chat(
  "Let's approach this from a different perspective. What if we...",
  new_conversation: true
)
```

## Working with Conversations Directly

You can also interact directly with a conversation:

```ruby
# Get a specific conversation
conversation = problematic.conversations.last

# Continue the conversation
response = conversation.chat("Can you elaborate on the third point?")

# Use a different provider for this message
response = conversation.chat(
  "Analyze these results with more detail",
  provider: advanced_provider
)
```

## Configuring Models

### Setting Default Tools

```ruby
class Method < ApplicationRecord
  include LlmToolkit::Conversable
  
  # All Method instances will use these tools by default
  default_tools LlmToolkit::Tools::StepGenerator, 
                LlmToolkit::Tools::ActionGenerator
end
```

### Custom Provider Selection

```ruby
class Subject < ApplicationRecord
  include LlmToolkit::Conversable
  
  # Set a custom method to determine the provider
  default_llm_provider_method :get_appropriate_provider
  
  def get_appropriate_provider
    # Logic to select the best provider based on context
    if title.length > 100
      # Complex subject might need a more capable model
      user.llm_providers.find_by(name: 'Claude Opus')
    else
      # Simpler subjects can use a faster model
      user.llm_providers.find_by(name: 'Claude Haiku') || 
        user.default_llm_provider
    end
  end
end
```

### Custom System Prompts

```ruby
class Resource < ApplicationRecord
  include LlmToolkit::Conversable
  
  # Set a custom method to generate system prompts
  default_system_prompt_method :resource_system_prompt
  
  def resource_system_prompt(role = nil)
    base_prompt = [
      "You are an expert at creating educational resources.",
      "The user is working on a methodology called '#{method.title}'."
    ]
    
    case role
    when :reviewer
      base_prompt + ["Focus on reviewing and improving the resources."]
    else
      base_prompt + ["Help create comprehensive, engaging resources."]
    end
  end
end
```

## Creating Custom Tools

### Basic Tool

```ruby
module LlmToolkit
  module Tools
    class BrainJuiceExtractor < AbstractTool
      def self.definition
        {
          name: "extract_brain_juice",
          description: "Extract key insights from user input to save as brain juice",
          input_schema: {
            type: "object",
            properties: {
              content: {
                type: "string",
                description: "The text to extract insights from",
              },
              max_insights: {
                type: "integer",
                description: "Maximum number of insights to extract",
              }
            },
            required: ["content"],
          }
        }
      end

      def self.execute(conversable:, args:, tool_use: nil)
        content = args['content']
        max_insights = args['max_insights'] || 3
        
        # Simple implementation - in reality you'd use NLP or the LLM itself
        insights = content.split('.').select { |s| s.length > 20 }.first(max_insights)
        
        # Store the insights as brain juice
        insights.each do |insight|
          conversable.brain_juice_entries.create!(content: insight)
        end
        
        { result: "Extracted #{insights.size} insights as brain juice." }
      rescue => e
        { error: "Error extracting brain juice: #{e.message}" }
      end
    end
  end
end
```

### Asynchronous Tool

For tools that need to perform background processing:

```ruby
module LlmToolkit
  module Tools
    class DocumentAnalyzer < AbstractTool
      def self.definition
        {
          name: "analyze_document",
          description: "Analyze a document with ID and extract key information",
          input_schema: {
            type: "object",
            properties: {
              document_id: {
                type: "integer",
                description: "The ID of the document to analyze",
              }
            },
            required: ["document_id"],
          }
        }
      end

      def self.execute(conversable:, args:, tool_use: nil)
        document_id = args['document_id']
        
        # Find the document
        document = Document.find_by(id: document_id)
        return { error: "Document not found" } unless document
        
        # Start a background job to process it
        job_id = DocumentAnalysisJob.perform_later(
          document_id: document_id,
          tool_use_id: tool_use.id
        )
        
        # Return an asynchronous result marker
        {
          state: "asynchronous_result",
          result: "Document analysis started in the background. Analysis job ID: #{job_id}"
        }
      rescue => e
        { error: "Error starting document analysis: #{e.message}" }
      end
    end
  end
end

# Background job to process the document
class DocumentAnalysisJob < ApplicationJob
  def perform(document_id:, tool_use_id:)
    document = Document.find(document_id)
    tool_use = LlmToolkit::ToolUse.find(tool_use_id)
    
    # Perform the analysis
    analysis_result = analyze_document(document)
    
    # Update the tool result
    tool_use.create_tool_result!(
      message: tool_use.message,
      content: analysis_result,
      pending: false
    )
    
    # Optionally continue the conversation with the result
    continue_conversation(tool_use, analysis_result)
  end
  
  private
  
  def analyze_document(document)
    # Your document analysis logic
  end
  
  def continue_conversation(tool_use, analysis_result)
    conversation = tool_use.message.conversation
    conversation.chat("I've completed the document analysis: #{analysis_result}")
  end
end
```

## Conversation Management Helpers

The `LlmToolkit` module provides a helper for managing conversations:

```ruby
# Ensure a conversation exists or create a new one
conversation = LlmToolkit.ensure_conversation(problematic)

# You can then use this conversation directly
response = conversation.chat("Tell me more about this subject")
```

## Error Handling

LLM calls can fail for various reasons (API errors, rate limits, etc.). Always handle errors appropriately:

```ruby
def chat_with_error_handling(problematic, message)
  begin
    response = problematic.chat(message)
    { success: true, response: response.content }
  rescue LlmToolkit::LlmProvider::ApiError => e
    Rails.logger.error("LLM API error: #{e.message}")
    { success: false, error: "LLM service error: #{e.message}" }
  rescue StandardError => e
    Rails.logger.error("Unexpected error in chat: #{e.message}")
    { success: false, error: "An unexpected error occurred" }
  end
end
```