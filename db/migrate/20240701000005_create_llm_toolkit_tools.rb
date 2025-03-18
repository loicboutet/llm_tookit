class CreateLlmToolkitTools < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_toolkit_tools do |t|
      t.string :name, null: false
      t.text :description, null: false

      t.timestamps
    end

    add_index :llm_toolkit_tools, :name, unique: true
  end
end