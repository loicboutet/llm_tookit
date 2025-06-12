module LlmToolkit
  module MessageHelper
    # Returns CSS classes for message styling based on message properties
    # @param message [LlmToolkit::Message] The message to get classes for
    # @return [String] CSS classes separated by spaces
    def message_css_classes(message)
      classes = ["llm-message"]
      
      # Add role-based classes
      classes << "#{message.role}-message"
      
      # Add error styling for error messages
      if message.is_error?
        classes << "error-message"
      end
      
      # Add finish reason classes
      if message.finish_reason.present?
        classes << "finish-#{message.finish_reason.parameterize}"
      end
      
      classes.join(" ")
    end
    
    # Determines if a message should be displayed with error styling
    # @param message [LlmToolkit::Message] The message to check
    # @return [Boolean] True if message should be styled as an error
    def error_message?(message)
      message.is_error? || message.finish_reason == 'error'
    end
    
    # Returns an appropriate icon for the message based on its type
    # @param message [LlmToolkit::Message] The message to get icon for
    # @return [String] Unicode emoji or symbol
    def message_icon(message)
      return "⚠️" if error_message?(message)
      return "🤖" if message.role == 'assistant'
      return "👤" if message.role == 'user'
      return "🔧" if message.role == 'tool'
      
      "💬" # Default icon
    end
  end
end