require 'test_helper'

module LlmToolkit
  class LlmProviderTest < ActiveSupport::TestCase
    test "call should handle nil system_messages" do
      provider = LlmProvider.new(provider_type: 'anthropic', api_key: 'test_key', name: 'Test Provider')
      
      # Stub the API call methods to avoid actual API calls
      provider.stubs(:call_anthropic).returns({})
      
      # Call with nil system_messages
      result = provider.call(nil, [], [])
      
      # This should not raise an error
      assert_equal({}, result)
    end
    
    test "call should handle nil conversation_history" do
      provider = LlmProvider.new(provider_type: 'anthropic', api_key: 'test_key', name: 'Test Provider')
      
      # Stub the API call methods to avoid actual API calls
      provider.stubs(:call_anthropic).returns({})
      
      # Call with nil conversation_history
      result = provider.call([], nil, [])
      
      # This should not raise an error
      assert_equal({}, result)
    end
    
    test "call should handle nil tools" do
      provider = LlmProvider.new(provider_type: 'anthropic', api_key: 'test_key', name: 'Test Provider')
      
      # Stub the API call methods to avoid actual API calls
      provider.stubs(:call_anthropic).returns({})
      
      # Call with nil tools
      result = provider.call([], [], nil)
      
      # This should not raise an error
      assert_equal({}, result)
    end
    
    test "standardize_response should handle nil values" do
      provider = LlmProvider.new(provider_type: 'anthropic', api_key: 'test_key', name: 'Test Provider')
      
      # Call the private method directly (using send for testing purposes)
      result = provider.send(:standardize_response, {
        'content' => nil,
        'model' => 'test-model',
        'role' => 'assistant',
        'stop_reason' => nil,
        'stop_sequence' => nil,
        'usage' => nil
      })
      
      # The method should handle nil values and return a well-formed hash
      assert_equal "", result['content']
      assert_equal [], result['tool_calls']
    end
    
    test "standardize_openrouter_response should handle nil values" do
      provider = LlmProvider.new(provider_type: 'openrouter', api_key: 'test_key', name: 'Test Provider')
      
      # Call the private method directly (using send for testing purposes)
      result = provider.send(:standardize_openrouter_response, {
        'choices' => [{
          'message' => {
            'content' => nil,
            'role' => 'assistant',
            'tool_calls' => nil
          },
          'finish_reason' => nil
        }],
        'model' => 'test-model',
        'usage' => nil
      })
      
      # The method should handle nil values and return a well-formed hash
      assert_equal "", result['content']
      assert_equal [], result['tool_calls']
    end
    
    test "format_tools_response_from_openrouter should handle nil tool_calls" do
      provider = LlmProvider.new(provider_type: 'openrouter', api_key: 'test_key', name: 'Test Provider')
      
      # Call the private method directly (using send for testing purposes)
      result = provider.send(:format_tools_response_from_openrouter, nil)
      
      # The method should handle nil values and return an empty array
      assert_equal [], result
    end
  end
end