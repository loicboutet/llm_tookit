module LlmToolkit
  module Tools
    class GetUrl < LlmToolkit::ToolDSL
      description "Fetch content from a URL using the Jina AI service. The URL must use HTTP or HTTPS protocol."
      
      param :url, desc: "The URL to fetch content from (must be HTTP/HTTPS)"
      
      def execute(conversable:, tool_use:, url:)
        # Validate URL format
        unless url.match?(/\Ahttps?:\/\//)
          return { error: "Invalid URL format. Must start with http:// or https://" }
        end
        
        Rails.logger.info "GetUrl: Fetching content from: #{url}"
        
        begin
          jina_service = LlmToolkit::JinaService.new
          content = jina_service.fetch_url_content(url)
          
          # Truncate the content if it's too large (prevents overwhelmingly large responses)
          truncated_content = content.truncate(30000)
          if truncated_content.length < content.length
            Rails.logger.info "GetUrl: Content truncated from #{content.length} to #{truncated_content.length} characters"
          end
          
          { result: truncated_content }
        rescue => e
          Rails.logger.error "GetUrl: Error fetching URL: #{e.message}"
          Rails.logger.error "GetUrl: #{e.backtrace.join("\n")}" if e.backtrace
          { error: "Error fetching URL: #{e.message}" }
        end
      end
    end
  end
end