# LLM Toolkit Tests

This directory contains tests for the LLM Toolkit engine, with a focus on ensuring robust error handling and nil-safety.

## Running the Tests

You can run all tests with:

```bash
cd library/llm_toolkit
bundle exec rake test
```

## Test Coverage

These tests specifically focus on ensuring our code properly handles nil values to prevent the "undefined method 'each' for nil" error. The tests include:

### CallLlmWithToolService Tests
- Handling nil system prompts
- Handling nil tool definitions
- Handling nil conversation history
- Handling nil LLM response content
- Handling nil tool calls in response

### LlmProvider Tests
- Handling nil system messages
- Handling nil conversation history
- Handling nil tools
- Handling nil values in response standardization

### ToolService Tests
- Ensuring tool_definitions never returns nil
- Handling nil or empty string inputs for tools

## Maintainability

When adding new functionality to the LLM Toolkit, be sure to:

1. Always check for nil values before calling methods on them
2. Use defensive programming techniques (nil checks, default values)
3. Add tests that specifically check edge cases with nil values
4. Log meaningful error messages
5. Wrap API calls in proper error handling

This will help maintain the robustness of the engine against unexpected inputs and API responses.