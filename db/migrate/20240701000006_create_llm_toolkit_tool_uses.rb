class CreateLlmToolkitToolUses < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_toolkit_tool_uses do |t|
      t.references :message, null: false, foreign_key: { to_table: :llm_toolkit_messages }
      t.string :name, null: false
      t.json :input
      t.string :tool_use_id
      t.integer :status, default: 0

      t.timestamps
    end
  end
end