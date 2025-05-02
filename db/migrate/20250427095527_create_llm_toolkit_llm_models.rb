class CreateLlmToolkitLlmModels < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_toolkit_llm_models do |t|
      t.string :name, null: false
      t.references :llm_provider, null: false, foreign_key: { to_table: :llm_toolkit_llm_providers }
      t.boolean :default, default: false, null: false

      t.timestamps
    end

    # Index for uniqueness of name within a provider
    add_index :llm_toolkit_llm_models, [:llm_provider_id, :name], unique: true

    # Index to ensure only one default model per provider at the database level
    # Note: The exact syntax for partial indexes might vary slightly depending on the database adapter (e.g., PostgreSQL vs SQLite).
    # This syntax is common for PostgreSQL. For SQLite, a CHECK constraint might be needed or handled at the application level.
    # Let's assume PostgreSQL or similar for now. If using SQLite, this index might need adjustment or removal.
    add_index :llm_toolkit_llm_models, [:llm_provider_id, :default], unique: true, where: '"default" = TRUE', name: 'index_llm_models_on_provider_id_and_default_true'
  end
end
