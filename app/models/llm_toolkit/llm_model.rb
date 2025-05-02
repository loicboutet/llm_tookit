module LlmToolkit
  class LlmModel < ApplicationRecord
    belongs_to :llm_provider, class_name: 'LlmToolkit::LlmProvider'

    validates :name, presence: true, uniqueness: { scope: :llm_provider_id }
    validates :default, uniqueness: { scope: :llm_provider_id }, if: :default?

    # Callback to ensure only one default is set per provider
    before_save :ensure_single_default, if: :default?

    scope :default, -> { where(default: true) }

    private

    def ensure_single_default
      # Unset other defaults for the same provider
      LlmModel.where(llm_provider_id: llm_provider_id)
              .where.not(id: id)
              .update_all(default: false)
    end
  end
end
