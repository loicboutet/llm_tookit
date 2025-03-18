class AddUserIdToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_toolkit_messages, :user_id, :integer
    add_index :llm_toolkit_messages, :user_id
  end
end