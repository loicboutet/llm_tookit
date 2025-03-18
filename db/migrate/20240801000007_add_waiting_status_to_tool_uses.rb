class AddWaitingStatusToToolUses < ActiveRecord::Migration[8.0]
  def up
    # Check if the status column exists and if it's an enum column
    if column_exists?(:llm_toolkit_tool_uses, :status) && 
       ActiveRecord::Base.connection.column_exists?(:llm_toolkit_tool_uses, :status)
      
      # Get the current status field definition
      column_type = ActiveRecord::Base.connection.columns(:llm_toolkit_tool_uses).find { |c| c.name == 'status' }.sql_type
      
      if column_type.start_with?('integer')
        # We're assuming it's already an integer enum, so we just need to update our code
        # No schema change needed here
      else
        # In case it's not an integer enum, we'd need to handle conversion
        # But this is unlikely in a fresh setup
        add_column :llm_toolkit_tool_uses, :status_new, :integer, default: 0
        
        # Migrate data if needed...
        
        remove_column :llm_toolkit_tool_uses, :status
        rename_column :llm_toolkit_tool_uses, :status_new, :status
      end
    else
      # If status doesn't exist, add it (unexpected but handled for safety)
      add_column :llm_toolkit_tool_uses, :status, :integer, default: 0
    end
  end

  def down
    # No action needed for rollback as we're just extending the enum
    # values in the code, not changing the schema
  end
end