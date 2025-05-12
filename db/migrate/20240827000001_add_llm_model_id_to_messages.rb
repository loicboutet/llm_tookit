class AddLlmModelIdToMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :llm_toolkit_messages, :llm_model, foreign_key: { to_table: :llm_toolkit_llm_models }, index: true
  end
end