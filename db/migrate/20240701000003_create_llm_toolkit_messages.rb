class CreateLlmToolkitMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_toolkit_messages do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :llm_toolkit_conversations }
      t.string :role, null: false
      t.text :content
      t.boolean :is_error
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_creation_input_tokens
      t.integer :cache_read_input_tokens

      t.timestamps
    end
  end
end