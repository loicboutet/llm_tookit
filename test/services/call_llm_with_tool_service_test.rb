require 'test_helper'

module LlmToolkit
  class CallLlmWithToolServiceTest < ActiveSupport::TestCase
    setup do
      # Mock the llm_provider
      @llm_provider = mock('LlmProvider')
      @llm_provider.stubs(:provider_type).returns('anthropic')
      
      # Mock the conversable
      @conversable = mock('Conversable')
      
      # Mock the conversation
      @conversation = mock('Conversation')
      @conversation.stubs(:conversable).returns(@conversable)
      @conversation.stubs(:update).returns(true)
      @conversation.stubs(:waiting?).returns(false)
      @conversation.stubs(:history).returns([])
      
      # Mock message
      @message = mock('Message')
      @message.stubs(:tool_uses).returns([])
      @message.stubs(:update).returns(true)
      
      # Mock conversation messages
      @messages = mock('Messages')
      @messages.stubs(:create!).returns(@message)
      @conversation.stubs(:messages).returns(@messages)
    end

    test "should handle nil system_prompt" do
      # Setup
      @conversable.stubs(:respond_to?).with(:generate_system_messages).returns(true)
      @conversable.stubs(:generate_system_messages).returns(nil)
      
      # Expect the LLM provider to be called with an empty array for system_prompt
      @llm_provider.expects(:call).with([], [], []).returns({
        'content' => 'Test response',
        'usage' => nil,
        'tool_calls' => nil
      })
      
      # Create and call the service
      service = LlmToolkit::CallLlmWithToolService.new(
        llm_provider: @llm_provider,
        conversation: @conversation
      )
      
      # Execute
      service.call
    end

    test "should handle empty tools array" do
      # Setup
      @conversable.stubs(:respond_to?).with(:generate_system_messages).returns(true)
      @conversable.stubs(:generate_system_messages).returns(['Test system message'])
      
      # tool_definitions now returns an empty array by design
      
      # Expect the LLM provider to be called with an empty array for tools
      @llm_provider.expects(:call).with(['Test system message'], [], []).returns({
        'content' => 'Test response',
        'usage' => nil,
        'tool_calls' => nil
      })
      
      # Create and call the service
      service = LlmToolkit::CallLlmWithToolService.new(
        llm_provider: @llm_provider,
        conversation: @conversation
      )
      
      # Execute
      service.call
    end

    test "should handle nil conversation history" do
      # Setup
      @conversable.stubs(:respond_to?).with(:generate_system_messages).returns(true)
      @conversable.stubs(:generate_system_messages).returns(['Test system message'])
      
      # Mock conversation to return nil history
      @conversation.stubs(:history).returns(nil)
      
      # Expect the LLM provider to be called with an empty array for conversation history
      @llm_provider.expects(:call).with(['Test system message'], [], []).returns({
        'content' => 'Test response',
        'usage' => nil,
        'tool_calls' => nil
      })
      
      # Create and call the service
      service = LlmToolkit::CallLlmWithToolService.new(
        llm_provider: @llm_provider,
        conversation: @conversation
      )
      
      # Execute
      service.call
    end

    test "should handle nil LLM response content" do
      # Setup
      @conversable.stubs(:respond_to?).with(:generate_system_messages).returns(true)
      @conversable.stubs(:generate_system_messages).returns(['Test system message'])
      
      # Expect the LLM provider to return nil content
      @llm_provider.expects(:call).with(['Test system message'], [], []).returns({
        'content' => nil,
        'usage' => nil,
        'tool_calls' => nil
      })
      
      # Expected behavior: should create a message with empty content
      @messages.expects(:create!).with(
        role: 'assistant', 
        content: ""
      ).returns(@message)
      
      # Create and call the service
      service = LlmToolkit::CallLlmWithToolService.new(
        llm_provider: @llm_provider,
        conversation: @conversation
      )
      
      # Execute
      service.call
    end

    test "should handle nil tool_calls in response" do
      # Setup
      @conversable.stubs(:respond_to?).with(:generate_system_messages).returns(true)
      @conversable.stubs(:generate_system_messages).returns(['Test system message'])
      
      # Expect the LLM provider to return nil tool_calls but stop_reason indicating tools
      @llm_provider.expects(:call).with(['Test system message'], [], []).returns({
        'content' => 'Test response',
        'usage' => nil,
        'tool_calls' => nil,
        'stop_reason' => 'tool_use'
      })
      
      # Create and call the service
      service = LlmToolkit::CallLlmWithToolService.new(
        llm_provider: @llm_provider,
        conversation: @conversation
      )
      
      # This should not raise an error, and handle the nil tool_calls gracefully
      service.call
    end
  end
end