module LlmToolkit
  class CallLlmWithToolService
    attr_reader :llm_provider, :conversation, :conversable, :role, :tools, :user_id, :tool_classes

    # Initialize the service with necessary parameters
    #
    # @param llm_provider [LlmProvider] The provider to use for LLM calls
    # @param conversation [Conversation] The conversation to update
    # @param tool_classes [Array<Class>] Optional tool classes to use
    # @param role [Symbol] Role to use for conversation history
    # @param user_id [Integer] ID of the user making the request
    def initialize(llm_provider:, conversation:, tool_classes: [], role: nil, user_id: nil)
      @llm_provider = llm_provider
      @conversation = conversation
      @conversable = conversation.conversable
      @role = role || conversation.agent_type.to_sym
      @user_id = user_id || Thread.current[:current_user_id]
      @tool_classes = tool_classes 

      # Use passed tool classes or get from ToolService
      @tools = if tool_classes.any?
        ToolService.build_tool_definitions(tool_classes)
      else
        ToolService.tool_definitions
      end
    end

    # Main method to call the LLM and process the response
    #
    # @return [Boolean] Success status
    def call
      # Return if LLM provider is missing
      return false unless @llm_provider

      begin
        # Set conversation to working status
        @conversation.update(status: :working)
        
        # Start the LLM interaction loop
        response = call_llm
        process_response(response)
        
        true
      rescue => e
        Rails.logger.error("Error in CallLlmWithToolService: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        false
      ensure
        # Set conversation status to resting when done, unless waiting for approval
        @conversation.update(status: :resting) unless @conversation.waiting?
      end
    end

    private

    # Process the LLM response and execute any tool calls
    #
    # @param response [Hash] The response from the LLM
    def process_response(response)
      return unless response
      
      # Create an assistant message with the response content
      message = create_message(response['content'])
      
      # Process tool calls in a loop until done or waiting for approval
      while response['tool_calls'].present?
        # Process tool uses and check if dangerous tools were encountered
        dangerous_tool_encountered = process_tool_uses(response, message)
        
        # If dangerous tools were encountered, break the loop and wait for approval
        break if dangerous_tool_encountered
        
        # Otherwise, call the LLM again with the updated conversation history
        response = call_llm
        break unless response
        
        # Create a new message with the response content
        message = create_message(response['content'])
      end
    end

    # Call the LLM and get a response
    #
    # @return [Hash] The response from the LLM
    def call_llm
      # Get system prompt
      sys_prompt = if @conversable.respond_to?(:generate_system_messages)
                     @conversable.generate_system_messages(@role)
                   else
                     []
                   end

      # Get conversation history
      conv_history = @conversation.history(@role, provider_type: @llm_provider.provider_type)

      # Call the LLM provider
      @llm_provider.call(sys_prompt, conv_history, @tools)
    end

    # Create a message with the LLM response
    #
    # @param content [String] The content of the message
    # @return [Message] The created message
    def create_message(content)
      @conversation.messages.create!(
        role: 'assistant',
        content: content,
        user_id: @user_id
      )
    end

    # Process tool uses from LLM response
    #
    # @param response [Hash] The LLM response
    # @param message [Message] The message object to attach tool uses to
    # @return [Boolean] Whether dangerous tools were encountered
    def process_tool_uses(response, message)
      tool_calls = response['tool_calls']
      return false unless tool_calls.is_a?(Array)

      dangerous_tool_encountered = false

      tool_calls.each do |tool_use|
        next unless tool_use.is_a?(Hash)

        name = tool_use['name'] || 'unknown_tool'
        input = tool_use['input'] || {}
        id = tool_use['id'] || SecureRandom.uuid

        saved_tool_use = message.tool_uses.create!(
          name: name,
          input: input,
          tool_use_id: id,
        )

        tool_list = tools || []
        if tool_list.any? { |tool| tool[:name] == tool_use['name'] }
          if saved_tool_use.dangerous?
            saved_tool_use.update(status: :pending)
            dangerous_tool_encountered = true
            @conversation.update(status: :waiting)
          else
            saved_tool_use.update(status: :approved)
            execute_tool(saved_tool_use)
          end
        else
          rejection_message = "The tool '#{tool_use['name']}' is not available in the current context. Please use only the tools provided in the system prompt."
          saved_tool_use.reject_with_message(rejection_message)
        end
      end

      dangerous_tool_encountered
    end

    # Execute a tool
    #
    # @param tool_use [ToolUse] The tool use record to execute
    # @return [Boolean] Success status
    def execute_tool(tool_use)
      # Find the tool class
      Rails.logger.info("@tool_classes #{@tool_classes}")
      Rails.logger.info("tool_use.name #{tool_use.name}")
      tool_class = @tool_classes.find { |tool| tool.definition[:name] == tool_use.name }
      return false unless tool_class

      # Execute the tool
      result = tool_class.execute(conversable: @conversable, args: tool_use.input, tool_use: tool_use)

      # Handle tool execution errors
      if result.is_a?(Hash) && result[:error].present?
        tool_use.reject_with_message(result[:error])
        return false
      end

      # Handle asynchronous results
      if result.is_a?(Hash) && result[:state] == "asynchronous_result"
        # For async tools, the tool_use is already in an approved state
        # but the tool_result will be updated later when the async response arrives
        tool_result = tool_use.create_tool_result!(
          message: tool_use.message,
          content: result[:result],
          pending: true
        )
        return true
      end

      # Create a tool result with the executed tool's result
      tool_result = tool_use.create_tool_result!(
        message: tool_use.message,
        content: result.to_s
      )

      true
    end
  end
end