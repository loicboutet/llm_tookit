module LlmToolkit
  class ToolResult < ApplicationRecord
    belongs_to :message, class_name: 'LlmToolkit::Message'
    belongs_to :tool_use, class_name: 'LlmToolkit::ToolUse'
    
    after_create :touch_conversation
    after_update :touch_conversation
    after_destroy :touch_conversation
    
    # Ensure is_error is always a boolean
    before_save :ensure_is_error_boolean
    
    private
    
    def ensure_is_error_boolean
      # Convert nil to false, and ensure any other value is explicitly a boolean
      self.is_error = self.is_error.nil? ? false : !!self.is_error
    end
    
    def touch_conversation
      message.conversation.touch
    end
  end
end