class CreateLlmToolkitLlmProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_toolkit_llm_providers do |t|
      t.string :name, null: false
      t.string :api_key, null: false
      t.string :provider_type, null: false
      t.json :settings
      t.references :owner, polymorphic: true, null: false

      t.timestamps
    end

    add_index :llm_toolkit_llm_providers, [:name, :owner_id, :owner_type], unique: true, name: 'index_llm_toolkit_providers_name_owner'
  end
end