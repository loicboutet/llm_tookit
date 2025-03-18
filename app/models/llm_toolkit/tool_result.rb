module LlmToolkit
  class ToolResult < ApplicationRecord
    belongs_to :message, class_name: 'LlmToolkit::Message'
    belongs_to :tool_use, class_name: 'LlmToolkit::ToolUse'
    
    after_create :touch_conversation
    after_update :touch_conversation
    after_destroy :touch_conversation
    
    private
    
    def touch_conversation
      message.conversation.touch
    end
  end
end