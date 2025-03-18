class CreateLlmToolkitToolResults < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_toolkit_tool_results do |t|
      t.references :message, null: false, foreign_key: { to_table: :llm_toolkit_messages }
      t.references :tool_use, null: false, foreign_key: { to_table: :llm_toolkit_tool_uses }
      t.text :content
      t.text :diff
      t.boolean :is_error

      t.timestamps
    end
  end
end