# Ensure Turbo::StreamsChannel is available
require 'turbo-rails' 

module LlmToolkit
  class CallStreamingLlmWithToolService
    # Rendering helpers removed - broadcasting raw chunks

    attr_reader :llm_provider, :conversation, :assistant_message, :conversable, :role, :tools, :user_id, :tool_classes

    # Initialize the service with necessary parameters
    #
    # @param llm_provider [LlmProvider] The provider to use for LLM calls
    # @param conversation [Conversation] The conversation context
    # @param assistant_message [Message] The pre-created empty assistant message record
    # @param tool_classes [Array<Class>] Optional tool classes to use
    # @param role [Symbol] Role to use for conversation history
    # @param user_id [Integer] ID of the user making the request
    def initialize(llm_provider:, conversation:, assistant_message:, tool_classes: [], role: nil, user_id: nil)
      @llm_provider = llm_provider
      @conversation = conversation
      @assistant_message = assistant_message # Store the passed message
      @conversable = conversation.conversable
      @role = role || conversation.agent_type.to_sym
      @user_id = user_id
      @tool_classes = tool_classes 

      # Use passed tool classes or get from ToolService
      @tools = if tool_classes.any?
        ToolService.build_tool_definitions(tool_classes)
      else
        ToolService.tool_definitions
      end
      
      # Initialize variables to track streamed content using the passed message
      @current_message = @assistant_message # Use the passed message
      @current_content = @current_message.content || "" # Initialize content from message
      @content_complete = false
      @content_chunks_received = @current_content.present?
      # @current_tool_calls = [] # Replaced by accumulated_tool_calls
      @accumulated_tool_calls = {} # Accumulate tool call chunks by index
      @processed_tool_call_ids = Set.new
      @special_url_input = nil
      @tool_results_pending = false
    end

    # Main method to call the LLM and process the streamed response
    # @return [Boolean] Success status
    def call
      # Return if LLM provider is missing
      return false unless @llm_provider

      # Validate provider supports streaming
      unless @llm_provider.provider_type == 'openrouter'
        Rails.logger.error("Streaming not supported for provider: #{@llm_provider.provider_type}")
        return false
      end

      begin
        # Set conversation to working status
        @conversation.update(status: :working)

        # Start the LLM streaming interaction
        stream_llm

        true
      rescue => e
        Rails.logger.error("Error in CallStreamingLlmWithToolService: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        false
      ensure
        # Set conversation status to resting when done, unless waiting for approval
        @conversation.update(status: :resting) unless @conversation.waiting?
      end
    end

    private

    # Stream responses from the LLM and process chunks
    def stream_llm
      # Get system prompt
      sys_prompt = if @conversable.respond_to?(:generate_system_messages)
                     @conversable.generate_system_messages(@role)
                   else
                     []
                   end

      # Get conversation history
      conv_history = @conversation.history(@role, provider_type: @llm_provider.provider_type)
      
      # NOTE: No need to create a message here, it's passed in via initialize
      
      # Call the LLM with streaming and handle each chunk
      final_response = @llm_provider.stream_chat(sys_prompt, conv_history, @tools) do |chunk|
        process_chunk(chunk)
      end

      # Final processing happens within the 'finish' chunk handler now.
      # Tool calls from the final_response might be redundant if streaming worked correctly,
      # but we keep this block as a fallback, although it might need review later
      # if it causes duplicate processing.
      if final_response && final_response['tool_calls'].present? && !@content_chunks_received && @accumulated_tool_calls.empty?
        Rails.logger.warn("Processing tool calls from final_response as no streaming chunks were processed.")
        # Format the tool calls from the final response
        formatted_tool_calls = @llm_provider.send(:format_tools_response_from_openrouter, final_response['tool_calls'])
        dangerous_encountered = process_tool_calls(formatted_tool_calls)

        # Make another call to the LLM with the tool results if we have some and no dangerous tools
        if !dangerous_encountered && @tool_results_pending
          # Add a small delay to ensure tool results are saved to the database
          sleep(0.5) 
          
          # Create a new message for the follow-up response
          Rails.logger.info("Making follow-up call to LLM with tool results from final response")
          followup_with_tools
        end
      end

      # Special case: If we collected a URL input but haven't created a get_url tool yet, create one now
      if @special_url_input && !@current_message.tool_uses.exists?(name: "get_url")
        dangerous_encountered = handle_special_url_tool
        
        # Make another call to the LLM with the tool results if no dangerous tools
        if !dangerous_encountered && @tool_results_pending
          # Add a small delay to ensure tool results are saved to the database
          sleep(0.5)
          
          # Create a new message for the follow-up response
          Rails.logger.info("Making follow-up call to LLM with tool results from special URL")
          followup_with_tools
        end
      end

      # Check if we have any tool results but haven't done a follow-up yet
      if @tool_results_pending && !@conversation.waiting?
        # Add a small delay to ensure tool results are saved to the database
        sleep(0.5)
        
        # Log that we're doing a follow-up after the end of streaming
        Rails.logger.info("Making follow-up call to LLM after end of streaming")
        followup_with_tools
      end
    end

    # Make a follow-up call to the LLM with the tool results
    def followup_with_tools
      # Skip if we're already waiting for approval
      return if @conversation.waiting?

      Rails.logger.info("Starting follow-up call to LLM with tool results")
      
      # Reset streaming variables
      @current_content = ""
      # @current_tool_calls = [] # Replaced
      @accumulated_tool_calls = {} # Reset accumulator
      @processed_tool_call_ids = Set.new
      @content_complete = false
      @content_chunks_received = false
      @tool_results_pending = false
      
      # Get updated conversation history with tool results
      sys_prompt = if @conversable.respond_to?(:generate_system_messages)
                     @conversable.generate_system_messages(@role)
                   else
                     []
                   end
      conv_history = @conversation.history(@role, provider_type: @llm_provider.provider_type)
      
      # Log the conversation history for debugging
      Rails.logger.debug("Follow-up conversation history size: #{conv_history.size}")
      
      # Create a new message for the followup response
      @current_message = create_empty_message
      
      # Call the LLM with streaming and handle each chunk
      final_response = @llm_provider.stream_chat(sys_prompt, conv_history, @tools) do |chunk|
        process_chunk(chunk)
      end

      # Handle any tool calls in the final response (if we didn't process them during streaming)
      if final_response && final_response['tool_calls'].present? && !@content_chunks_received
        dangerous_encountered = process_tool_calls(final_response['tool_calls'])
        
        # Recursively call followup_with_tools if we have more tool results
        if !dangerous_encountered && @tool_results_pending
          sleep(0.5)
          followup_with_tools
        end
      end
    end

    # Process an individual chunk from the streaming response
    # @param chunk [Hash] The chunk data from the streamed response
    def process_chunk(chunk)
      case chunk[:chunk_type]
      when 'content'
        # Append content to the current message
        @current_content += chunk[:content]
        @content_chunks_received = true

        # Update the database record (use update_column to avoid callbacks/broadcasts)
        # Update the database record (still useful to save the final state)
        # Update the database record (still useful to save the final state)
        @current_message.update(content: @current_content)

        # Broadcast Turbo Stream append action targeting the *inner content div* ID
        # target_id = "#{ActionView::RecordIdentifier.dom_id(@current_message)}_content" 
        # Turbo::StreamsChannel.broadcast_append_to(
        #   # Use the stream name derived from the conversation model instance
        #   @conversation.to_gid_param, 
        #   target: target_id, # Target the inner div
        #   content: chunk[:content] # Send the raw chunk content
        # )

      when 'tool_call_update'
        # Accumulate tool call updates based on index
        chunk[:tool_calls].each do |partial_tool_call|
          index = partial_tool_call['index']
          next unless index.is_a?(Integer) # Ensure we have a valid index

          @accumulated_tool_calls[index] ||= {}
          # Use deep_merge! to combine nested structures like the 'function' hash
          @accumulated_tool_calls[index].deep_merge!(partial_tool_call)
        end
        # @current_tool_calls is no longer used here

      when 'finish'
        @content_complete = true

        # If we accumulated tool calls, process them
        unless @accumulated_tool_calls.empty?
          complete_tool_calls = @accumulated_tool_calls.values.sort_by { |tc| tc['index'] || 0 } # Sort by index just in case
          Rails.logger.debug "Accumulated complete tool calls: #{complete_tool_calls.inspect}"

          # Examine the *complete* tool calls for special handling
          examine_tool_calls_for_special_cases(complete_tool_calls)

          # Format the tool calls to our internal format
          formatted_tool_calls = @llm_provider.send(:format_tools_response_from_openrouter, complete_tool_calls)
          Rails.logger.debug "Formatted tool calls for processing: #{formatted_tool_calls.inspect}"

          process_tool_calls(formatted_tool_calls)
        end
        # Reset accumulator for potential follow-up calls
        @accumulated_tool_calls = {}
      end
    end
    
    # Examine tool calls for special cases like get_url with URL as a separate tool call
    # @param tool_calls [Array] The raw tool calls from the streaming response
    def examine_tool_calls_for_special_cases(tool_calls)
      return unless tool_calls.is_a?(Array)
      
      # Look for get_url tools without URL
      get_url_tools = tool_calls.select { |tc| tc.dig("function", "name") == "get_url" }
      
      # Look for URL in other tool calls
      url_tools = tool_calls.select do |tc| 
        function_args = tc.dig("function", "arguments") || "{}"
        args = begin
          JSON.parse(function_args) rescue {}
        end
        tc.dig("function", "name") != "get_url" && args["url"].present?
      end
      
      # If we found both a get_url tool and a tool with a URL, store the URL
      if get_url_tools.any? && url_tools.any?
        url_tool = url_tools.first
        function_args = url_tool.dig("function", "arguments") || "{}"
        args = begin
          JSON.parse(function_args) rescue {}
        end
        
        @special_url_input = args["url"] if args["url"].present?
        
        Rails.logger.debug("Found special case: get_url tool and a URL in another tool: #{@special_url_input}")
      end
    end
    
    # Handle the special case of a get_url tool where the URL is in a separate tool call
    # @return [Boolean] Whether a dangerous tool was encountered
    def handle_special_url_tool
      return false unless @special_url_input
      
      Rails.logger.debug("Creating special get_url tool with URL: #{@special_url_input}")
      
      # Create a tool use for get_url with the URL from the other tool
      saved_tool_use = @current_message.tool_uses.create!(
        name: "get_url",
        input: { "url" => @special_url_input },
        tool_use_id: SecureRandom.uuid
      )
      
      # Process this tool
      dangerous_tool = false
      if saved_tool_use.dangerous?
        saved_tool_use.update(status: :pending)
        @conversation.update(status: :waiting)
        dangerous_tool = true
      else
        saved_tool_use.update(status: :approved)
        execute_tool(saved_tool_use)
        @tool_results_pending = true
      end
      
      # Clear the special URL input
      @special_url_input = nil
      
      dangerous_tool
    end
    
    # Process tool calls detected during streaming
    # @param tool_calls [Array] Array of tool call definitions
    # @return [Boolean] Whether a dangerous tool was encountered
    def process_tool_calls(tool_calls)
      return false unless tool_calls.is_a?(Array) && tool_calls.any?
      
      dangerous_tool_encountered = false
      
      # First, see if we can find any get_url tool and tool with URL parameter
      get_url_tool = tool_calls.find { |tc| tc["name"] == "get_url" }
      url_tool = tool_calls.find do |tc| 
        tc["input"].is_a?(Hash) && tc["input"]["url"].present? && tc["name"] != "get_url"
      end
      
      # If we found both, combine them
      if get_url_tool && url_tool && get_url_tool["input"].empty?
        get_url_tool["input"] = { "url" => url_tool["input"]["url"] }
        
        # Remove the URL tool from the list
        tool_calls = tool_calls.reject { |tc| tc == url_tool }
      end
      
      # Now process each valid tool call
      tool_calls.each do |tool_use|
        next unless tool_use.is_a?(Hash)
        
        # Skip if we've already processed this tool_call_id
        if tool_use['id'].present? && @processed_tool_call_ids.include?(tool_use['id'])
          next
        end
        
        # Add to processed IDs if we have an ID
        @processed_tool_call_ids << tool_use['id'] if tool_use['id'].present?
        
        # Skip tools with nil names
        next if tool_use['name'].nil?
        
        # Skip unknown_tool (we handle these specially)
        next if tool_use['name'] == 'unknown_tool'
        
        # Log tool use for debugging
        Rails.logger.debug("Processing streamed tool use: #{tool_use.inspect}")
        
        name = tool_use['name']
        input = tool_use['input'] || {}
        id = tool_use['id'] || SecureRandom.uuid
        
        # Special handling for get_url with empty input, when we have a special URL
        if name == "get_url" && input.empty? && @special_url_input.present?
          input = { "url" => @special_url_input }
          @special_url_input = nil
        end
        
        # Log the extracted data
        Rails.logger.debug("Tool name: #{name}")
        Rails.logger.debug("Tool input: #{input.inspect}")
        Rails.logger.debug("Tool ID: #{id}")
        
        # Check if this tool is already registered for this message
        existing_tool_use = @current_message.tool_uses.find_by(name: name)
        if existing_tool_use
          Rails.logger.debug("Tool use with name #{name} already exists, updating")
          existing_tool_use.update(input: input)
          saved_tool_use = existing_tool_use
        else
          saved_tool_use = @current_message.tool_uses.create!(
            name: name,
            input: input,
            tool_use_id: id,
          )
        end
        
        # Only process the tool use if it doesn't have a result yet
        if saved_tool_use.tool_result.nil?
          tool_list = @tools || []
          if tool_list.any? { |tool| tool[:name] == name }
            if saved_tool_use.dangerous?
              saved_tool_use.update(status: :pending)
              dangerous_tool_encountered = true
              @conversation.update(status: :waiting)
            else
              saved_tool_use.update(status: :approved)
              execute_tool(saved_tool_use)
              @tool_results_pending = true
            end
          else
            rejection_message = "The tool '#{name}' is not available in the current context. Please use only the tools provided in the system prompt."
            saved_tool_use.reject_with_message(rejection_message)
          end
        end
      end
      
      # Check for special case: we have a URL but no get_url tool
      if @special_url_input && !@current_message.tool_uses.exists?(name: "get_url") && !dangerous_tool_encountered
        dangerous_tool = handle_special_url_tool
        dangerous_tool_encountered ||= dangerous_tool
      end
      
      dangerous_tool_encountered
    end
    
    # Execute a tool
    # @param tool_use [ToolUse] The tool use record to execute
    # @return [Boolean] Success status
    def execute_tool(tool_use)
      # Find the tool class
      Rails.logger.info("@tool_classes #{@tool_classes}")
      Rails.logger.info("tool_use.name #{tool_use.name}")
      tool_class = @tool_classes.find { |tool| tool.definition[:name] == tool_use.name }
      return false unless tool_class
      
      begin
        # Log the tool definition for debugging
        Rails.logger.info("Tool definition for #{tool_class}: #{tool_class.definition}")
        
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
      rescue => e
        # Log the error
        Rails.logger.error("Error executing tool #{tool_use.name}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        
        # Create a tool result with the error
        tool_use.create_tool_result!(
          message: tool_use.message,
          content: "Error executing tool: #{e.message}",
          is_error: true
        )
        
        false
      end
    end

    # Create a new empty message for the follow-up response
    # This is needed internally when tools are executed and a new LLM call is made.
    def create_empty_message
      @conversation.messages.create!(
        role: 'assistant',
        content: '', # Start empty
        # llm_provider_id: @llm_provider.id, # Removed provider association
        user_id: @user_id # Ensure user_id is associated if available
      )
    end
  end
end
