class AddPendingToLlmToolkitToolResults < ActiveRecord::Migration[8.0]
  def change
    add_column :llm_toolkit_tool_results, :pending, :boolean, default: false
  end
end