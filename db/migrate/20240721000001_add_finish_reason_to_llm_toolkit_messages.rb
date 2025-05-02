class AddFinishReasonToLlmToolkitMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_toolkit_messages, :finish_reason, :string
  end
end