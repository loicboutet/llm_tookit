namespace :llm_toolkit do
  desc "Migrate existing LlmProviders to create default LlmModels"
  task populate_default_llm_models: :environment do
    puts "Starting migration to populate default LlmModels..."

    LlmToolkit::LlmProvider.find_each do |provider|
      puts "Processing provider: #{provider.name} (ID: #{provider.id}, Type: #{provider.provider_type})"

      # Determine the model name previously used
      model_name = provider.settings&.dig('model')
      if model_name.blank?
        case provider.provider_type
        when 'anthropic'
          model_name = LlmToolkit.config.default_anthropic_model
          puts "  Provider settings missing 'model', using default Anthropic model: #{model_name}"
        when 'openrouter'
          model_name = LlmToolkit.config.default_openrouter_model
          puts "  Provider settings missing 'model', using default OpenRouter model: #{model_name}"
        else
          puts "  WARN: Provider settings missing 'model' and unknown provider type '#{provider.provider_type}'. Cannot determine default model name."
          next # Skip this provider
        end
      else
        puts "  Found model name in provider settings: #{model_name}"
      end

      if model_name.blank?
        puts "  ERROR: Could not determine a model name for provider #{provider.name}. Skipping."
        next
      end

      # Check if a default model already exists (e.g., if task is run multiple times)
      if provider.llm_models.exists?(default: true)
        puts "  Provider already has a default model. Skipping creation."
        next
      end
      
      # Check if a model with this name already exists for this provider
      existing_model = provider.llm_models.find_by(name: model_name)

      if existing_model
        puts "  Model '#{model_name}' already exists. Marking it as default."
        # Ensure no other model is default first (though the callback should handle this)
        provider.llm_models.where.not(id: existing_model.id).update_all(default: false)
        existing_model.update!(default: true)
      else
        puts "  Creating new default model '#{model_name}'."
        begin
          provider.llm_models.create!(name: model_name, default: true)
          puts "  Successfully created default model '#{model_name}'."
        rescue ActiveRecord::RecordInvalid => e
          puts "  ERROR: Failed to create default model '#{model_name}' for provider #{provider.name}. Validation errors: #{e.record.errors.full_messages.join(', ')}"
        rescue => e
          puts "  ERROR: An unexpected error occurred while creating model '#{model_name}' for provider #{provider.name}: #{e.message}"
        end
      end
    end

    puts "Finished populating default LlmModels."
  end
end
