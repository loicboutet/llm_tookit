class CreateLlmToolkitConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_toolkit_conversations do |t|
      t.references :conversable, polymorphic: true, null: false
      t.integer :agent_type, default: 0
      t.string :status, default: "resting"
      t.boolean :canceled, default: false
      t.datetime :canceled_at, null: true
      t.references :canceled_by, polymorphic: true, null: true

      t.timestamps
    end

    add_index :llm_toolkit_conversations, :agent_type
    add_index :llm_toolkit_conversations, :status
    add_index :llm_toolkit_conversations, :canceled
    add_index :llm_toolkit_conversations, :canceled_at
  end
end