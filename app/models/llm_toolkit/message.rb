# Include ActionView helpers needed for dom_id
include ActionView::RecordIdentifier

module LlmToolkit
  class Message < ApplicationRecord
    belongs_to :conversation, touch: true
    # belongs_to :llm_provider, class_name: 'LlmToolkit::LlmProvider', optional: true # Removed association
    # belongs_to :llm_model, class_name: 'LlmToolkit::LlmModel', optional: true # Removed association
    has_many :tool_uses, class_name: 'LlmToolkit::ToolUse', dependent: :destroy
    has_many :tool_results, class_name: 'LlmToolkit::ToolResult', dependent: :destroy

    # Broadcast appending new assistant messages and replacing updated ones
    after_create_commit :broadcast_append_to_list, if: :llm_content?
    after_update_commit :broadcast_replace_in_list, if: -> { saved_change_to_content? && !saved_change_to_api_total_tokens? }
    # Broadcast usage stats update when tokens change
    after_update_commit :broadcast_usage_stats_update, if: :saved_change_to_api_total_tokens?

    # Appends the new message partial to the conversation's message list
    def broadcast_append_to_list
      # Find the previous message in the conversation to determine its role
      previous_message = conversation.messages.order(created_at: :asc).where("created_at < ?", self.created_at).last
      previous_role = previous_message&.role

      broadcast_append_later_to(
        conversation,                         # Stream name derived from the conversation
        target: "conversation-messages",      # The ID of the div inside the messages frame
        partial: "messages/message",          # The message partial
        locals: { message: self, previous_message_role: previous_role } # Pass previous role
      )
    end

    # Replaces the existing message partial when content changes
    def broadcast_replace_in_list
      # Find the previous message in the conversation to determine its role
      previous_message = conversation.messages.order(created_at: :asc).where("created_at < ?", self.created_at).last
      previous_role = previous_message&.role

      broadcast_replace_later_to(
        conversation,                         # same stream you subscribe to
        target: dom_id(self),                 # Target the entire message div for replacement
        partial: "messages/message",          # The message partial
        locals: { message: self, previous_message_role: previous_role } # Pass previous role
      )
    end
    # Attachments for user uploads (images, PDFs)
    has_many_attached :attachments

    validates :role, presence: true
    
    # Support for ActiveStorage if it's available and properly set up
    if defined?(ActiveStorage) && ActiveRecord::Base.connection.table_exists?('active_storage_attachments')
      has_many_attached :images
      after_save :deduplicate_images, if: -> { images.attached? }
    end

    scope :non_error, -> { where(is_error: [nil, false]) }

    def for_llm(llm_role = :coder, provider_type = "anthropic")
      if llm_role == :coder
        if role == 'user'
          if content.blank? && provider_type == "openrouter"
            {role: role, content: nil}
          else
            {role: role, content: [type: "text", text: content.blank? ? "Empty message" : content]}
          end
        else 
          {role: role, content: content.blank? ? nil : content}
        end
      else 
        if role == 'user'
          {role: "assistant", content: [type: "text", text: content]}
        else 
          {role: "user", content: content.blank? ? "Empty message" : content}
        end
      end
    end

    def user_message?
      role == 'user'
    end

    def llm_content?
      role == 'assistant'
    end

    def total_tokens
      input_tokens.to_i + cache_creation_input_tokens.to_i + cache_read_input_tokens.to_i + output_tokens.to_i
    end

    def calculate_cost
      (input_tokens.to_i * 0.000003) +
      (cache_creation_input_tokens.to_i * 0.00000375) +
      (cache_read_input_tokens.to_i * 0.0000003) +
      (output_tokens.to_i * 0.000015)
    end
    
    # For backward compatibility - returns false if ActiveStorage isn't available
    def images_attached?
      return false unless respond_to?(:images)
      images.attached?
    end
    
    # Provides a user-friendly description of the finish_reason
    def finish_reason_description
      case finish_reason
      when 'stop'
        'Model completed response normally'
      when 'length'
        'Response cut off due to token limit'
      when 'tool_calls'
        'Model called tools to complete the task'
      when 'content_filter'
        'Content was filtered due to safety concerns'
      when nil
        'No finish reason provided'
      else
        finish_reason.to_s.humanize
      end
    end
    
    private
    
    # Broadcasts an update to the conversation's usage stats frame
    def broadcast_usage_stats_update
      broadcast_replace_later_to(
        conversation,
        target: dom_id(conversation, "usage_stats"), # Target the turbo frame
        partial: "conversations/usage_stats",
        locals: { conversation: conversation }
      )
    end

    def deduplicate_images
      return if images.blank?

      unique_blobs = images.blobs.uniq(&:checksum)
      self.images = unique_blobs
    end
  end
end