module LlmToolkit
  class LlmProvider < ApplicationRecord
    module SystemMessageFormatter
      extend ActiveSupport::Concern
      
      private
      
      # Format system messages for OpenRouter, handling both simple and complex formats
      def format_system_messages_for_openrouter(system_messages)
        return [] if system_messages.blank?
        
        # Check if we have complex OpenRouter format (array of message objects)
        if complex_system_messages?(system_messages)
          Rails.logger.info "Using complex system message format for OpenRouter"
          return system_messages
        end
        
        # Convert simple format to OpenRouter format
        Rails.logger.info "Converting simple system messages to OpenRouter format"
        system_message_content = system_messages.map { |msg| 
          msg.is_a?(Hash) ? msg[:text] : msg.to_s 
        }.join("\n")
        
        [{
          role: 'system',
          content: [{ type: 'text', text: system_message_content }]
        }]
      end
      
      # Check if system messages are in complex OpenRouter format
      def complex_system_messages?(system_messages)
        return false unless system_messages.is_a?(Array)
        return false if system_messages.empty?
        
        # Complex format: array of message objects with role and content
        system_messages.all? do |msg|
          msg.is_a?(Hash) && 
          msg[:role].present? && 
          msg[:content].is_a?(Array) &&
          msg[:content].all? { |content_item| content_item.is_a?(Hash) && content_item[:type].present? }
        end
      end
      
      # Format system messages for Anthropic (keep existing simple format)
      def format_system_messages_for_anthropic(system_messages)
        return "You are an AI assistant." if system_messages.blank?
        
        # For Anthropic, we only use the text content from system messages
        if complex_system_messages?(system_messages)
          # Extract text from complex format
          text_parts = []
          system_messages.each do |msg|
            msg[:content].each do |content_item|
              if content_item[:type] == 'text'
                text_parts << content_item[:text]
              end
            end
          end
          text_parts.join("\n")
        else
          # Simple format
          system_messages.map { |msg| 
            msg.is_a?(Hash) ? msg[:text] : msg.to_s 
          }.join("\n")
        end
      end
    end
  end
end