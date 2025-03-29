module LlmToolkit
  class Conversation < ApplicationRecord
    belongs_to :conversable, polymorphic: true, touch: true
    belongs_to :canceled_by, polymorphic: true, optional: true
    has_many :messages, class_name: 'LlmToolkit::Message', dependent: :destroy
    has_many :tool_uses, through: :messages, class_name: 'LlmToolkit::ToolUse'

    broadcasts_refreshes

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
        message_content = message.for_llm(role, provider_type)
        message_content[:content] = format_content_with_images(message, message_content[:content])

        tool_uses = message.tool_uses
        
        # Handle messages without tools
        unless tool_uses.any?
          history_messages << message_content
          next
        end

        # Handle non-coder roles
        if role != :coder
          message_content[:content] += format_non_coder_tool_results(tool_uses)
          history_messages << message_content
          next
        end

        # Handle coder role with tools based on provider
        case provider_type
        when "anthropic"
          # Anthropic format: Tool uses and results are part of the message content array
          history_messages += format_anthropic_message(message_content, tool_uses)
        when "openrouter"
          # OpenRouter format: Tool uses are function calls, results are function messages
          history_messages += format_openrouter_message(message_content, tool_uses)
        end
      end

      # Only add cache control headers for Anthropic
      if provider_type == "anthropic"
        add_cache_control(history_messages)
      end
      
      if provider_type == "anthropic"
        return history_messages.reject { |msg| msg[:content].nil? || (msg[:content].is_a?(Array) && msg[:content].empty?) } 
      else
        return history_messages
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

    # Message formatting methods
    def format_content_with_images(message, content)
      if message.respond_to?(:images) && message.images.attached?
        image_content = message.images.map do |image|
          {
            type: "image",
            source: {
              type: "base64",
              media_type: image.content_type,
              data: Base64.strict_encode64(image.download)
            }
          }
        end
        image_content << { type: "text", text: message.content.present? ? message.content : "" } 
        image_content
      elsif content.is_a?(String)
        [{ type: "text", text: content }]
      elsif content.nil? 
        nil
      else
        Array(content)
      end
    end

    def format_anthropic_message(message_content, tool_uses)
      messages = [{
        role: message_content[:role],
        content: message_content[:content]
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
            role: "user",
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
      messages = [{
        role: message_content[:role],
        content: message_content[:content] || ""
      }]

      tool_uses.each do |tool_use|
        # Generate a valid tool ID if one doesn't exist
        tool_id = tool_use.tool_use_id.presence || "tool_#{SecureRandom.hex(4)}_#{tool_use.name}"
        
        # Ensure input is properly JSON serialized
        tool_arguments = begin
          if tool_use.input.is_a?(Hash)
            tool_use.input.to_json
          else
            JSON.generate({})
          end
        rescue => e
          Rails.logger.error("Error serializing tool arguments: #{e.message}")
          "{}"
        end
        
        # Add the function call
        if message_content[:content].nil?
          messages.first[:tool_calls] ||= []
          messages.first[:tool_calls] << {
            id: tool_id,
            type: "function",
            function: {
              name: tool_use.name,
              arguments: tool_arguments
            }
          }
        else 
          messages << {
            role: "assistant",
            content: nil,
            tool_calls: [{
              id: tool_id,
              type: "function",
              function: {
                name: tool_use.name,
                arguments: tool_arguments
              }
            }]
          }
        end  

        # Add the function result if present
        if tool_result = tool_use.tool_result
          # Format the content properly for OpenRouter
          tool_result_content = tool_result.content.to_s
          
          # Clean up any Ruby object notation
          if tool_result_content.include?('=>')
            Rails.logger.warn("Ruby hash notation detected in tool result, cleaning up")
            # Try to extract actual content from Ruby object notation
            if tool_result_content =~ /:result\s*=>\s*"(.*?)"/
              tool_result_content = $1
            end
          end
          
          # Add the tool result message
          messages << {
            role: "tool",
            tool_call_id: tool_id,
            name: tool_use.name,
            content: tool_result_content
          }
        end
      end
      
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
        { type: "text", text: result_content }
      end.compact
    end

    def add_cache_control(history_messages)
      user_messages = history_messages.select { |msg| msg[:role] == "user" }
      last_two_user_messages = user_messages.last(2)
      
      last_two_user_messages.each do |msg|
        if msg[:content].is_a?(Array) && msg[:content].any?
          msg[:content].last[:cache_control] = { type: "ephemeral" }
        end
      end
    end
  end
end