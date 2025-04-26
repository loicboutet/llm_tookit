module LlmToolkit
  class Conversation < ApplicationRecord
    belongs_to :conversable, polymorphic: true, touch: true
    belongs_to :canceled_by, polymorphic: true, optional: true
    has_many :messages, class_name: 'LlmToolkit::Message', dependent: :destroy
    has_many :tool_uses, through: :messages, class_name: 'LlmToolkit::ToolUse'

    # Explicitly declare the attribute type for the enum
    attribute :agent_type, :integer
    attribute :status, :string

    # Now define the enums
    enum :agent_type, {
      planner: 0,
      coder: 1,
      reviewer: 2,
      tester: 3
    }, prefix: true

    enum :status, {
      resting: "resting",
      working: "working",
      waiting: "waiting"
    }, prefix: true

    validates :agent_type, presence: true
    validates :status, presence: true

    # Add broadcast_refreshes if the host app has it set up
    if defined?(ApplicationRecord.broadcast_refreshes)
      broadcasts_refreshes
    end

    # Chat interface - send message and get response
    # @param message [String] The message to send to the LLM
    # @param provider [LlmToolkit::LlmProvider, nil] An optional specific provider to use
    # @param tools [Array<Class>, nil] Optional tools to use for this interaction
    # @param async [Boolean] Whether to process the request asynchronously
    # @return [LlmToolkit::Message] The assistant's response message or nil if async
    def chat(message, provider: nil, tools: nil, async: false)
      # Set conversation status to working
      update(status: :working)
      
      # Get the LLM provider
      llm_provider = provider || get_default_provider
      
      # Get the tools
      tool_classes = tools || get_default_tools
      
      # Add user message
      user_message = messages.create!(
        role: 'user',
        content: message,
        user_id: Thread.current[:current_user_id]
      )
      
      if async
        # Run in background job
        LlmToolkit::CallLlmJob.perform_later(
          id, 
          llm_provider.id, 
          tool_classes.map(&:name),
          self.agent_type,
          Thread.current[:current_user_id]
        )
        
        # Return true to indicate the job was queued
        return true
      else
        # Call LLM service synchronously
        service = LlmToolkit::CallLlmWithToolService.new(
          llm_provider: llm_provider,
          conversation: self,
          tool_classes: tool_classes,
          user_id: Thread.current[:current_user_id]
        )
        
        # Process the response
        result = service.call
        
        # Return the last assistant message
        messages.where(role: 'assistant').order(created_at: :desc).first if result
      end
    end

    # Streaming chat interface - send message and get streamed response
    # @param message [String] The message to send to the LLM
    # @param provider [LlmToolkit::LlmProvider, nil] An optional specific provider to use
    # @param tools [Array<Class>, nil] Optional tools to use for this interaction
    # @param broadcast_to [String, nil] Optional channel to broadcast chunks to
    # @param async [Boolean] Whether to process the request asynchronously
    # @return [LlmToolkit::Message, Boolean] The assistant's response message or true if async
    def stream_chat(message, provider: nil, tools: nil, broadcast_to: nil, async: true)
      # Validation - currently stream_chat only works with openrouter provider
      llm_provider = provider || get_default_provider
      unless llm_provider.provider_type == 'openrouter'
        raise ArgumentError, "stream_chat only works with OpenRouter providers"
      end
      
      # Set conversation status to working
      update(status: :working)
      
      # Get the tools
      tool_classes = tools || get_default_tools
      
      # Add user message
      user_message = messages.create!(
        role: 'user',
        content: message,
        user_id: Thread.current[:current_user_id]
      )
      
      if async
        # Run in background job with optional broadcast channel
        LlmToolkit::CallStreamingLlmJob.perform_later(
          id, 
          llm_provider.id, 
          tool_classes.map(&:name),
          self.agent_type,
          Thread.current[:current_user_id],
          broadcast_to
        )
        
        # Return true to indicate the job was queued
        return true
      else
        # Call streaming LLM service synchronously
        service = LlmToolkit::CallStreamingLlmWithToolService.new(
          llm_provider: llm_provider,
          conversation: self,
          tool_classes: tool_classes,
          user_id: Thread.current[:current_user_id]
        )
        
        # Process the response without a callback (synchronous operation)
        result = service.call
        
        # Return the last assistant message
        messages.where(role: 'assistant').order(created_at: :desc).first if result
      end
    end

    # Asynchronous chat interface
    # @param message [String] The message to send to the LLM
    # @param provider [LlmToolkit::LlmProvider, nil] An optional specific provider to use
    # @param tools [Array<Class>, nil] Optional tools to use for this interaction
    # @return [Boolean] Success status of job queueing
    def chat_async(message, provider: nil, tools: nil)
      chat(message, provider: provider, tools: tools, async: true)
    end
    
    # Asynchronous streaming chat interface
    # @param message [String] The message to send to the LLM
    # @param provider [LlmToolkit::LlmProvider, nil] An optional specific provider to use
    # @param tools [Array<Class>, nil] Optional tools to use for this interaction
    # @param broadcast_to [String, nil] Optional channel to broadcast chunks to
    # @return [Boolean] Success status of job queueing
    def stream_chat_async(message, provider: nil, tools: nil, broadcast_to: nil)
      stream_chat(message, provider: provider, tools: tools, broadcast_to: broadcast_to, async: true)
    end

    def working?
      status == "working"
    end

    def waiting?
      status == "waiting"
    end

    def can_send_message?
      status_resting? || canceled?
    end

    def can_retry?
      status_resting? && messages.last&.is_error?
    end

    # Returns an array of messages formatted for LLM providers
    #
    # @param role [Symbol] Either :coder, :reviewer, or :planner
    # @param provider_type [String] Either 'anthropic' or 'openrouter'
    #
    # @return [Array<Hash>] Formatted messages for the specified provider
    def history(role = :coder, provider_type: "anthropic")
      raise ArgumentError, "Invalid role" unless [:coder, :reviewer, :planner].include?(role)
      raise ArgumentError, "Invalid provider type" unless ["anthropic", "openrouter"].include?(provider_type)

      role = :coder if role == :planner
      history_messages = []
      
      messages.non_error.order(:created_at).each do |message|
        # Base structure for the message
        llm_message = { role: message.role }
        tool_uses = message.tool_uses

        # --- Content Formatting ---
        if message.user_message?
          # User messages: Handle text and attachments (OpenRouter specific)
          content_parts = []
          # Always add text part first, even if empty, as recommended by OpenRouter
          content_parts << { type: "text", text: message.content.presence || "" }

          if message.attachments.attached?
            message.attachments.each do |attachment|
              begin
                # Download blob data safely
                blob_data = attachment.blob.download
                base64_data = Base64.strict_encode64(blob_data)

                if attachment.image? && ['image/jpeg', 'image/png', 'image/webp'].include?(attachment.content_type)
                  data_url = "data:#{attachment.content_type};base64,#{base64_data}"
                  content_parts << { type: "image_url", image_url: { url: data_url } }
                elsif attachment.content_type == 'application/pdf'
                  data_url = "data:application/pdf;base64,#{base64_data}"
                  content_parts << {
                    type: "file",
                    file: {
                      filename: attachment.filename.to_s,
                      file_data: data_url
                    }
                  }
                else
                  Rails.logger.warn "Unsupported attachment type for LLM: #{attachment.content_type}, filename: #{attachment.filename}"
                  # Optionally add a text note about the unsupported file
                  # content_parts << { type: "text", text: "[Unsupported attachment: #{attachment.filename}]" }
                end
              rescue => e
                Rails.logger.error "Error processing attachment #{attachment.id} for LLM: #{e.message}"
                # Optionally add a text note about the error
                # content_parts << { type: "text", text: "[Error processing attachment: #{attachment.filename}]" }
              end
            end
          end
          
          # Assign the constructed content array
          llm_message[:content] = content_parts

        elsif message.llm_content?
          # Assistant messages: Handle text and tool calls
          # Text content is handled first
          llm_message[:content] = message.content.presence # Keep as string for now, tool formatting might adjust

          # Tool calls are handled later in format_openrouter_message / format_anthropic_message
        else
          # Other roles (e.g., tool results) might be handled differently
          llm_message[:content] = message.content.presence
        end
        # --- End Content Formatting ---


        # --- Tool Handling ---
        if tool_uses.any? && role == :coder # Only coder role uses tools in LLM calls for now
          case provider_type
          when "anthropic"
            # Anthropic format: Tool uses and results are part of the message content array
            # Note: Anthropic attachment format differs, this needs specific handling if used
            history_messages += format_anthropic_message(llm_message, tool_uses)
          when "openrouter"
            # OpenRouter format: Tool uses are function calls, results are function messages
            history_messages += format_openrouter_message(llm_message, tool_uses)
          end
        else
          # Add message without tools if it has content or is a user message (even empty)
          # Skip empty non-user messages without tools
          if llm_message[:content].present? || llm_message[:role] == 'user'
            # Ensure content is correctly formatted (string for assistant, array for user if needed)
            if llm_message[:role] == 'assistant' && llm_message[:content].is_a?(Array)
              # Find the text part for simple assistant messages
              text_part = llm_message[:content].find { |part| part[:type] == 'text' }
              llm_message[:content] = text_part ? text_part[:text] : ""
            end
             # OpenRouter expects user content to be an array even if just text
            if llm_message[:role] == 'user' && provider_type == 'openrouter' && llm_message[:content].is_a?(String)
              llm_message[:content] = [{ type: "text", text: llm_message[:content] }]
            end
            history_messages << llm_message
          end
        end
        # --- End Tool Handling ---
      end

      # Only add cache control headers for Anthropic
      if provider_type == "anthropic"
        add_cache_control(history_messages)
      end

      # Clean up potentially empty messages before returning
      # For OpenRouter, user messages can have empty text if they only contain files
      return history_messages.reject do |msg|
        is_empty_non_user = msg[:role] != 'user' && msg[:content].blank? && msg[:tool_calls].blank?
        is_empty_anthropic_user = provider_type == "anthropic" && msg[:role] == 'user' && msg[:content].is_a?(Array) && msg[:content].all? { |p| p[:text].blank? }
        is_empty_non_user || is_empty_anthropic_user
      end
    end

    private
    
    # Get the default provider from the conversable
    def get_default_provider
      if conversable.respond_to?(conversable.class.get_default_llm_provider_method)
        conversable.send(conversable.class.get_default_llm_provider_method)
      else
        conversable.default_llm_provider
      end
    end
    
    # Get the default tools from the conversable
    def get_default_tools
      conversable.class.default_tools
    end

    # Message formatting methods (Keep format_anthropic_message, format_openrouter_message, etc.)
    # Remove format_content_with_images as it's integrated above
    # def format_content_with_images(message, content) ... end # REMOVED

    def format_anthropic_message(message_content, tool_uses)
      # Ensure message_content[:content] is an array for Anthropic
      base_content = message_content[:content]
      if base_content.is_a?(String)
        message_content[:content] = [{ type: "text", text: base_content }]
      elsif base_content.nil?
         message_content[:content] = []
      end
      
      messages = [{
        role: message_content[:role],
        content: message_content[:content] # Should be an array now
      }]
      
      tool_uses.each do |tool_use|
        messages.first[:content] ||= []
        messages.first[:content] << {
          type: "tool_use",
          id: tool_use.tool_use_id,
          name: tool_use.name,
          input: tool_use.input
        }

        # Add the function result if present
        if tool_result = tool_use.tool_result
          # Ensure is_error is a boolean - this fixes the API error
          is_error_value = tool_result.is_error.nil? ? false : !!tool_result.is_error
          
          messages << {
            role: "user", # Tool results are user role for Anthropic
            content: [{
              type: "tool_result",
              tool_use_id: tool_use.tool_use_id,
              content: tool_result.content,
              is_error: is_error_value  # Always send a boolean value
            }]
          }
        end
      end

      messages
    end

    def format_openrouter_message(message_content, tool_uses)
      # Initial message part (user or assistant text/attachments)
      # Content should already be formatted correctly by the main loop
      messages = [message_content] 
      
      # Filter out the initial message if it's an assistant message that will ONLY contain tool_calls
      # User messages with attachments should always be included
      is_assistant_only_tools = message_content[:role] == 'assistant' && message_content[:content].blank?
      messages.shift if is_assistant_only_tools

      assistant_tool_call_message = nil
      tool_result_messages = []

      tool_uses.each do |tool_use|
        # Generate a valid tool ID if one doesn't exist
        tool_id = tool_use.tool_use_id.presence || "tool_#{SecureRandom.hex(4)}_#{tool_use.name}"
        
        # Ensure input is properly JSON serialized
        tool_arguments = begin
          if tool_use.input.is_a?(Hash)
            tool_use.input.to_json
          else
            JSON.generate({}) # Default to empty JSON object if input is not a hash
          end
        rescue JSON::GeneratorError => e
          Rails.logger.error("Error serializing tool arguments for tool #{tool_use.name} (ID: #{tool_id}): #{e.message}. Input: #{tool_use.input.inspect}")
          "{ \"error\": \"Failed to serialize arguments\" }" # Provide valid JSON error object
        rescue => e
           Rails.logger.error("Unexpected error serializing tool arguments for tool #{tool_use.name} (ID: #{tool_id}): #{e.message}")
           "{ \"error\": \"Unexpected error serializing arguments\" }"
        end
        
        # Create or add to the assistant message containing tool calls
        unless assistant_tool_call_message
          assistant_tool_call_message = {
            role: "assistant",
            content: nil, # Assistant message for tool calls has null content
            tool_calls: []
          }
        end
        
        assistant_tool_call_message[:tool_calls] << {
          id: tool_id,
          type: "function",
          function: {
            name: tool_use.name,
            arguments: tool_arguments
          }
        }

        # Add the function result if present
        if tool_result = tool_use.tool_result
          # Format the content properly for OpenRouter
          tool_result_content = tool_result.content.to_s
          
          # Clean up any Ruby object notation (basic attempt)
          if tool_result_content.include?('=>') && tool_result_content.strip.start_with?('{') && tool_result_content.strip.end_with?('}')
             begin
               # Attempt to parse as JSON first
               parsed = JSON.parse(tool_result_content)
               tool_result_content = parsed.to_json # Re-serialize to ensure valid JSON
             rescue JSON::ParserError
               # If JSON parsing fails, try a simple regex for common patterns
               Rails.logger.warn("Ruby hash notation detected in tool result, attempting cleanup for tool #{tool_use.name}")
               if tool_result_content =~ /:result\s*=>\s*"(.*?)"/m # Match multiline result string
                 tool_result_content = $1
               elsif tool_result_content =~ /:result\s*=>\s*(.*?)\s*(?:,\s*:|\})/m # Match non-string result
                 tool_result_content = $1
               else
                  # Fallback: Keep original if cleanup fails
                  Rails.logger.warn("Could not reliably clean Ruby hash notation for tool #{tool_use.name}")
               end
             end
          end
          
          # Add the tool result message
          tool_result_messages << {
            role: "tool",
            tool_call_id: tool_id,
            name: tool_use.name,
            content: tool_result_content
          }
        end
      end
      
      # Add the assistant tool call message if it was created
      messages << assistant_tool_call_message if assistant_tool_call_message
      
      # Add all tool result messages
      messages += tool_result_messages
      
      # Log the formatted messages for debugging
      Rails.logger.debug("Formatted OpenRouter messages: #{messages.inspect}")
      
      messages
    end

    def format_non_coder_tool_results(tool_uses)
      tool_uses.map do |tool_use|
        next unless tool_result = tool_use.tool_result
        result_content = if tool_result.diff.present?
          tool_result.diff
        elsif tool_result.content.present?
          tool_result.content
        else
          "Empty string"
        end
        # Non-coder results are just text added to the assistant message
        # This logic might need review depending on how non-coder roles use attachments/tools
        result_content # Return plain text
      end.compact.join("\n\n") # Join results into a single string
    end

    def add_cache_control(history_messages)
      user_messages = history_messages.select { |msg| msg[:role] == "user" }
      last_two_user_messages = user_messages.last(2)
      
      last_two_user_messages.each do |msg|
        # Ensure content is an array before trying to access the last element
        if msg[:content].is_a?(Array) && msg[:content].any?
          # Ensure the last element is a hash before adding cache_control
          if msg[:content].last.is_a?(Hash)
            msg[:content].last[:cache_control] = { type: "ephemeral" }
          end
        end
      end
    end
  end
end
