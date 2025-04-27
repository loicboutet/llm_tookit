module LlmToolkit
  module Tools
    class GetUrl < LlmToolkit::ToolDSL
      description "Fetch content from a URL using the Jina AI service. The URL must use HTTP or HTTPS protocol."
      
      param :url, desc: "The URL to fetch content from (must be HTTP/HTTPS)"

      # Metadata for display purposes
      def self.display_metadata
        {
          french_name: "Consulter une URL",
          icon: "bi bi-link-45deg",
          displayed_args: ["url"]
        }
      end
      
      def execute(conversable:, tool_use:, url:)
        # Validate URL format
        unless url.match?(/\Ahttps?:\/\//)
          return { error: "Invalid URL format. Must start with http:// or https://" }
        end
        
        Rails.logger.info "GetUrl: Fetching content from: #{url}"
        
        begin
          jina_service = LlmToolkit::JinaService.new
          content = jina_service.fetch_url_content(url)
                    
          # Convert result to properly formatted JSON string to ensure it's formatted correctly for OpenRouter
          { result: "Title: #{url}\n\n#{content}" }
        rescue => e
          Rails.logger.error "GetUrl: Error fetching URL: #{e.message}"
          Rails.logger.error "GetUrl: #{e.backtrace.join("\n")}" if e.backtrace
          { error: "Error fetching URL: #{e.message}" }
        end
      end
    end
  end
end
