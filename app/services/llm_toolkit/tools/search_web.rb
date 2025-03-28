module LlmToolkit
  module Tools
    class SearchWeb < LlmToolkit::ToolDSL
      description "Execute a search query using the Jina AI service to find relevant information"
      
      param :query, desc: "The search query to execute"
      param :country_code, desc: "Optional: Country code for search localization (e.g., 'US', 'GB')", required: false
      param :language_code, desc: "Optional: Language code for search results (e.g., 'en', 'fr')", required: false
      param :results_count, type: :integer, desc: "Optional: Number of search results to return (default: 10)", required: false
      param :page, type: :integer, desc: "Optional: Page number for pagination (default: 1)", required: false
      param :site, desc: "Optional: Limit search to a specific domain", required: false
      param :with_links_summary, type: :boolean, desc: "Optional: Include a summary of all links at the end", required: false
      param :with_images_summary, type: :boolean, desc: "Optional: Include a summary of all images at the end", required: false
      param :no_cache, type: :boolean, desc: "Optional: Bypass cache and retrieve real-time data", required: false
      
      def execute(conversable:, tool_use:, query:, country_code: nil, language_code: nil, 
                  results_count: nil, page: nil, site: nil, with_links_summary: false, 
                  with_images_summary: false, no_cache: false)
        
        # Validate required fields
        return { error: "Search query cannot be empty" } if query.blank?
        
        Rails.logger.info "SearchWeb: Executing search for: #{query}"
        
        # Build options hash
        options = {}
        options[:gl] = country_code if country_code.present?
        options[:hl] = language_code if language_code.present?
        options[:num] = results_count.to_s if results_count.present?
        options[:page] = page.to_s if page.present?
        options[:site] = site if site.present?
        options[:with_links_summary] = with_links_summary
        options[:with_images_summary] = with_images_summary
        options[:no_cache] = no_cache
        
        Rails.logger.info "SearchWeb: Options: #{options.inspect}"
        
        begin
          jina_service = LlmToolkit::JinaService.new
          results = jina_service.search(query, options)
          
          # Parse the JSON result for better processing by the LLM
          begin
            parsed_results = JSON.parse(results)
            
            if parsed_results.is_a?(Hash) && parsed_results['data'].is_a?(Array)
              # Format search results as a clean string for better compatibility with OpenRouter
              formatted_text = "SEARCH RESULTS FOR: #{query}\n\n"
              
              parsed_results['data'].each_with_index do |item, index|
                formatted_text += "---\n"
                formatted_text += "RESULT #{index + 1}:\n"
                formatted_text += "Title: #{item['title']}\n"
                formatted_text += "URL: #{item['url']}\n"
                
                if item['description'].present?
                  formatted_text += "Description: #{item['description']}\n"
                end
                
                if item['content'].present?
                  # Truncate content to keep result size manageable
                  content_preview = item['content'].to_s.truncate(500)
                  formatted_text += "Content Preview: #{content_preview}\n"
                end
                
                formatted_text += "\n"
              end
              
              Rails.logger.info "SearchWeb: Found #{parsed_results['data'].size} results"
              return { result: formatted_text }
            else
              # For non-standard responses, create a plain text representation
              formatted_text = "SEARCH RESULTS FOR: #{query}\n\n"
              formatted_text += "Raw Results: #{parsed_results.inspect.truncate(5000)}"
              return { result: formatted_text }
            end
          rescue JSON::ParserError => e
            Rails.logger.error "SearchWeb: JSON parsing error: #{e.message}"
            Rails.logger.error "SearchWeb: Response was: #{results.truncate(500)}"
            
            # Return a simpler plain text for OpenRouter
            return { result: "Error parsing search results. Raw response:\n\n#{results.truncate(5000)}" }
          end
        rescue => e
          Rails.logger.error "SearchWeb: Error performing search: #{e.message}"
          Rails.logger.error "SearchWeb: #{e.backtrace.join("\n")}" if e.backtrace
          return { error: "Error performing web search: #{e.message}" }
        end
      end
    end
  end
end