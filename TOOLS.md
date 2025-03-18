# LlmToolkit Tool Development Guide

This guide explains how to create new tools for LlmToolkit using our RubyLLM-inspired interface.

## What are Tools?

Tools allow LLMs to perform actions in your application. When an LLM needs to create data, fetch information, or modify content, it can use tools to interact with your application's business logic.

## Creating a Tool

To create a new tool, inherit from `LlmToolkit::ToolDSL` and use the DSL to define parameters and the execution logic:

```ruby
module LlmToolkit
  module Tools
    class MyTool < LlmToolkit::ToolDSL
      # Define tool description
      description "Description of what your tool does"
      
      # Define parameters
      param :parameter_name, desc: "Description of the parameter"
      param :optional_param, desc: "Description of an optional parameter", required: false
      param :integer_param, type: :integer, desc: "A parameter that should be an integer"
      
      # Implement the execute method with named parameters
      def execute(conversable:, tool_use:, parameter_name:, optional_param: nil, integer_param:)
        # Your implementation here
        
        # Return success result
        { result: "Operation successful" }
        
        # Or return error
        # { error: "Something went wrong" }
      end
    end
  end
end
```

## Tool DSL Reference

### `description`

Sets the tool description that will be sent to the LLM.

```ruby
description "Gets weather information for a location"
```

### `param`

Defines a parameter the tool accepts.

```ruby
param :name, type: :string, desc: "Description of the parameter", required: true
```

Options:
- `type`: The parameter type (`:string`, `:integer`, `:boolean`, `:number`, `:array`, `:object`)
- `desc`: Human-readable description of the parameter
- `required`: Whether the parameter is required (default: `true`)

### `execute` Method

This is where you implement the tool's functionality. It must have the following parameters:

- `conversable`: The object that initiated the conversation (e.g., a Problematic)
- `tool_use`: The ToolUse record representing this tool invocation
- Named parameters matching each param you defined

## Return Format

Your execute method should return a hash in one of these formats:

### Success Result

```ruby
{ result: "Success message or data" }
```

Or with structured data:

```ruby
{ 
  result: {
    id: record.id,
    name: record.name,
    success: true
  }
}
```

### Error Result

```ruby
{ error: "Error message explaining what went wrong" }
```

## Asynchronous Tools

For long-running operations, return a special format to indicate asynchronous processing:

```ruby
{
  state: "asynchronous_result",
  result: "Initial message to show while processing"
}
```

Then update the tool result later with a background job.

## Best Practices

1. **Validate Inputs**: Always validate inputs before performing operations
2. **Error Handling**: Use proper error handling with informative messages
3. **Logging**: Log important operations for debugging
4. **Security**: Be careful with tools that modify data - consider marking them as dangerous
5. **Documentation**: Provide clear descriptions for your tool and its parameters

## Example Tools

### Subject Generator

```ruby
class SubjectGenerator < LlmToolkit::ToolDSL
  description "Creates subject objects for a problematic"
  
  param :title, desc: "The title of the subject (3-7 words)"
  param :description, desc: "The description of the subject (2-4 sentences)"
  param :brain_juice, desc: "Optional brain juice insights", required: false
  
  def execute(conversable:, tool_use:, title:, description:, brain_juice: nil)
    # Validate inputs
    return { error: "Title cannot be empty" } if title.blank?
    
    # Create the subject
    subject = conversable.subjects.create!(
      title: title,
      description: description,
      brain_juice: brain_juice
    )
    
    { result: "Subject created: #{subject.title}" }
  rescue => e
    { error: "Failed to create subject: #{e.message}" }
  end
end
```

### Weather Tool

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