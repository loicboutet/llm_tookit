module LlmToolkit
  class ToolUse < ApplicationRecord
    belongs_to :message, class_name: 'LlmToolkit::Message'
    has_one :tool_result, class_name: 'LlmToolkit::ToolResult', dependent: :destroy
    
    # Explicitly declare the attribute type
    attribute :status, :integer
    enum :status, { pending: 0, approved: 1, rejected: 2, waiting: 3 }, prefix: true
      
    after_create :touch_conversation
    after_update :touch_conversation
    after_destroy :touch_conversation
    
    def dangerous?
      LlmToolkit.config.dangerous_tools.include?(name)
    end

    def completed?
      !status_pending? && !status_waiting?
    end
    
    def file_content
      if name == 'write_to_file' && status_approved?
        File.read(input['path'])
      end
    rescue Errno::ENOENT
      "File not found: #{input['path']}"
    end
    
    def reject_with_message(rejection_message)
      create_tool_result!(
        message: message,
        content: rejection_message,
        is_error: false
      )
      status_rejected!
    end
    
    private
    
    def touch_conversation
      message.conversation.touch
    end
  end
end