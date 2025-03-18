module LlmToolkit
  class Message < ApplicationRecord
    belongs_to :conversation, touch: true
    has_many :tool_uses, class_name: 'LlmToolkit::ToolUse', dependent: :destroy
    has_many :tool_results, class_name: 'LlmToolkit::ToolResult', dependent: :destroy
    
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
    
    private

    def deduplicate_images
      return if images.blank?

      unique_blobs = images.blobs.uniq(&:checksum)
      self.images = unique_blobs
    end
  end
end