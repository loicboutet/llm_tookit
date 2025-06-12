class AddIsErrorToLlmToolkitMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_toolkit_messages, :is_error, :boolean, default: false, null: false
  end
end