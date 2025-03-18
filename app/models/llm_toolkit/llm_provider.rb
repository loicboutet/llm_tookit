module LlmToolkit
  class LlmProvider < ApplicationRecord
    belongs_to :owner, polymorphic: true
    
    validates :name, presence: true, uniqueness: { scope: [:owner_id, :owner_type] }
    validates :api_key, presence: true
    validates :provider_type, presence: true, inclusion: { in: %w[anthropic openrouter] }

    class ApiError < StandardError; end

    def call(system_messages, conversation_history, tools = nil)
      # Ensure we have valid arrays
      system_messages = Array(system_messages)
      conversation_history = Array(conversation_history)
      tools = Array(tools)
      
      # Validate tools format
      tools.each do |tool|
        unless tool.is_a?(Hash) && tool[:name].present? && tool[:description].present?
          Rails.logger.warn "Invalid tool format detected: #{tool.inspect}"
          
          # Provide a default description if missing
          if tool[:name].present? && tool[:description].nil?
            tool[:description] = "Tool for #{tool[:name]}"
            Rails.logger.info "Added default description for tool: #{tool[:name]}"
          end
        end
      end
      
      case provider_type
      when 'anthropic'
        call_anthropic(system_messages, conversation_history, tools)
      when 'openrouter'
        call_openrouter(system_messages, conversation_history, tools)
      else
        raise ApiError, "Unsupported provider type: #{provider_type}"
      end
    end

    private

    def call_anthropic(system_messages, conversation_history, tools = nil)
      client = Faraday.new(url: 'https://api.anthropic.com') do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 300 # Set timeout to 5 minutes
        f.options.open_timeout = 10 # Set open timeout to 10 seconds
      end

      tools = Array(tools)
      all_tools = tools.presence || LlmToolkit::ToolService.tool_definitions
      
      Rails.logger.info("Tools count: #{all_tools.size}")
      all_tools.each_with_index do |tool, idx|
        Rails.logger.info("Tool #{idx+1}: #{tool[:name]} - Desc: #{tool[:description] || 'MISSING!'}")
      end

      model = settings&.dig('model') || LlmToolkit.config.default_anthropic_model
      max_tokens = settings&.dig('max_tokens').to_i || LlmToolkit.config.default_max_tokens
      Rails.logger.info("Max tokens : #{max_tokens}")

      request_body = {
        model: model,
        system: system_messages,
        messages: conversation_history,
        tools: all_tools,
        max_tokens: max_tokens
      }
      request_body[:tool_choice] = {type: "auto"} if tools.present?
    
      Rails.logger.info("System Messages: #{system_messages}")
      Rails.logger.info("Conversation History: #{conversation_history}")
      
      # Detailed request logging
      if Rails.env.development?
        Rails.logger.debug "ANTHROPIC REQUEST BODY: #{JSON.pretty_generate(request_body)}"
      end

      response = client.post('/v1/messages') do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['x-api-key'] = api_key
        req.headers['anthropic-version'] = '2023-06-01'
        req.headers['anthropic-beta'] = 'prompt-caching-2024-07-31'
        req.body = request_body.to_json
      end

      if response.success?
        Rails.logger.info("LlmProvider - Received successful response from Anthropic API:")
        Rails.logger.info(response.body)
        standardize_response(response.body)
      else
        Rails.logger.error("Anthropic API error: #{response.body}")
        raise ApiError, "API error: #{response.body['error']['message']}"
      end
    rescue Faraday::Error => e
      Rails.logger.error("Anthropic API error: #{e.message}")
      raise ApiError, "Network error: #{e.message}"
    end

    def call_openrouter(system_messages, conversation_history, tools = nil)
      client = Faraday.new(url: 'https://openrouter.ai/api/v1') do |f|
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
        f.options.timeout = 300
        f.options.open_timeout = 10
      end

      # Ensure system_messages is properly formatted and not nil
      system_message_content = if system_messages.present?
                                 system_messages.map { |msg| msg.is_a?(Hash) ? msg[:text] : msg.to_s }.join("\n")
                               else
                                 "You are an AI assistant."
                               end

      messages = [
        { role: 'system', content: system_message_content }
      ] + Array(conversation_history)

      model = settings&.dig('model') || 'anthropic/claude-3-sonnet'
      max_tokens = settings&.dig('max_tokens') || LlmToolkit.config.default_max_tokens

      request_body = {
        model: model,
        messages: messages,
        stream: false,
        max_tokens: max_tokens
      }

      tools = Array(tools)
      if tools.present?
        request_body[:tools] = format_tools_for_openrouter(tools)
        request_body[:tool_choice] = { type: 'auto' }
      end

      Rails.logger.info("OpenRouter Request - Messages: #{messages}")
      Rails.logger.info("OpenRouter Request - Tools: #{request_body[:tools] || []}")
      
      # Detailed request logging
      if Rails.env.development?
        Rails.logger.debug "OPENROUTER REQUEST BODY: #{JSON.pretty_generate(request_body)}"
      end

      response = client.post('chat/completions') do |req|
        req.headers['Content-Type'] = 'application/json'
        req.headers['Authorization'] = "Bearer #{api_key}"
        req.headers['HTTP-Referer'] = LlmToolkit.config.referer_url
        req.headers['X-Title'] = 'Development Environment'
        req.body = request_body.to_json
      end

      if response.success?
        Rails.logger.info("LlmProvider - Received successful response from OpenRouter API:")
        Rails.logger.info(response.body)
        standardize_openrouter_response(response.body)
      else
        Rails.logger.error("OpenRouter API error: #{response.body}")
        raise ApiError, "API error: #{response.body['error']&.[]('message') || response.body}"
      end
    rescue Faraday::Error => e
      Rails.logger.error("OpenRouter API error: #{e.message}")
      raise ApiError, "Network error: #{e.message}"
    end

    # Standardize the Anthropic API response to our internal format
    def standardize_response(response)
      content = response.dig('content', 0, 'text')
      tool_calls = response['content'].select { |c| c['type'] == 'tool_use' } if response['content'].is_a?(Array)
      
      {
        'content' => content || "",
        'model' => response['model'],
        'role' => response['role'],
        'stop_reason' => response['stop_reason'],
        'stop_sequence' => response['stop_sequence'],
        'tool_calls' => tool_calls || [],
        'usage' => response['usage']
      }
    end

    # Convert OpenRouter response to match our standardized format
    def standardize_openrouter_response(response)
      {
        'content' => response.dig('choices', 0, 'message', 'content') || "",
        'model' => response['model'],
        'role' => response.dig('choices', 0, 'message', 'role'),
        'stop_reason' => response.dig('choices', 0, 'finish_reason'),
        'stop_sequence' => nil,
        'tool_calls' => format_tools_response_from_openrouter(response.dig('choices', 0, 'message', 'tool_calls')),
        'usage' => response['usage']
      }
    end

    def format_tools_response_from_openrouter(tool_calls)
      return [] if tool_calls.nil?
      tool_calls.map do |tool_call|
        {
          "name" => tool_call.dig("function", "name"),
          "input" => begin
                       JSON.parse(tool_call.dig("function", "arguments"))
                     rescue
                       {}
                     end,
          "id" => tool_call["id"]
        }
      end
    end

    def format_tools_for_openrouter(tools)
      return [] if tools.nil?
      tools.map do |tool|
        {
          type: "function",
          function: {
            name: tool[:name],
            description: tool[:description] || "Tool for #{tool[:name]}",
            parameters: tool[:input_schema]
          }
        }
      end
    end
  end
end