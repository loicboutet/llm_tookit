require 'http'
require 'uri'

module LlmToolkit
  class JinaService
    READER_URL = 'https://r.jina.ai'.freeze
    SEARCH_URL = 'https://s.jina.ai'.freeze

    class Error < StandardError; end
    class ApiError < Error; end

    def initialize
      @api_key = Rails.application.credentials.dig(:jina, :api_key)
      raise Error, 'Jina API key not found in credentials' if @api_key.blank?
    end

    def fetch_url_content(url)
      Rails.logger.info "JinaService: Fetching content for URL: #{url}"
      
      # For the Jina reader API, the target URL needs to be encoded as path parameter 
      # after the reader URL (r.jina.ai)
      target_url = if url.start_with?(READER_URL)
        url # Already properly formatted
      else
        # Remove protocol (http/https) and encode the rest as a path
        clean_url = url.sub(/^https?:\/\//, '')
        "#{READER_URL}/#{clean_url}"
      end
      
      Rails.logger.info "JinaService: Making request to: #{target_url}"
      
      response = HTTP.headers(default_headers).get(target_url)
      handle_response(response)
    end
    
    def search(query, options = {})
      Rails.logger.info "JinaService: Searching for: #{query}"
      
      payload = {
        q: query,
        gl: options[:gl] || "US",
        hl: options[:hl] || "en",
        num: options[:num] || "10",
        page: options[:page] || "1"
      }
      
      headers = default_headers.merge({
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "X-Respond-With" => options[:respond_with] || "no-content"
      })
      
      # Add optional headers if provided
      headers["X-Site"] = options[:site] if options[:site].present?
      headers["X-With-Links-Summary"] = "true" if options[:with_links_summary]
      headers["X-With-Images-Summary"] = "true" if options[:with_images_summary]
      headers["X-No-Cache"] = "true" if options[:no_cache]
      headers["X-With-Generated-Alt"] = "true" if options[:with_generated_alt]
      
      Rails.logger.info "JinaService: Search request headers: #{headers.inspect}"
      Rails.logger.info "JinaService: Search request payload: #{payload.inspect}"
      
      response = HTTP.headers(headers)
                  .post(SEARCH_URL, json: payload)
                  
      handle_response(response)
    end

    private

    def handle_response(response)
      unless response.status.success?
        error_message = "HTTP Error: #{response.status} - Body: #{response.body.to_s.truncate(500)}"
        Rails.logger.error "JinaService: #{error_message}"
        raise ApiError, error_message
      end

      response.body.to_s
    end

    def default_headers
      {
        'Authorization' => "Bearer #{@api_key}"
      }
    end
  end
end