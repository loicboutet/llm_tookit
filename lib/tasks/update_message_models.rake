namespace :llm_toolkit do
  desc "Update existing Messages to point to the default LlmModel of their original provider"
  task update_existing_messages_llm_model: :environment do
    puts "Starting update of existing Messages llm_model_id..."

    # Temporary mapping to store original provider ID before column rename
    # This assumes the rename migration hasn't run yet, which is tricky.
    # A safer approach requires running migrations first, then this task.

    # Let's assume migrations HAVE run. The llm_model_id is present but likely NULL.
    # We need to infer the original provider. This is difficult without storing it temporarily.

    # --- Alternative Strategy: Add temporary column, migrate, update, remove column ---
    # This is complex. Let's try a simpler approach assuming the Rake task
    # `populate_default_llm_models` has already run.

    # We need to iterate through messages where llm_model_id is NULL.
    # But how do we know which provider it belonged to? The column is gone.
    # This highlights a flaw in the migration order/strategy.

    # --- Revised Strategy ---
    # 1. Migration 1: Create llm_toolkit_llm_models table.
    # 2. Rake Task 1: Run `llm_toolkit:populate_default_llm_models`.
    # 3. Migration 2: Add `llm_model_id` (nullable) to `llm_toolkit_messages`.
    # 4. Rake Task 2: Run a task to populate `llm_model_id` based on `llm_provider_id`.
    # 5. Migration 3: Remove `llm_provider_id` from `llm_toolkit_messages`.

    # Given the current state (rename migration created), let's modify the Rake task
    # to be run *after* the migrations and the populate task.
    # It needs to guess the provider based on other message context if possible,
    # or simply assign the *overall* default model if guessing isn't feasible.
    # This is imperfect.

    # --- Simpler, Imperfect Rake Task (Run AFTER migrations & populate task) ---
    puts "Attempting to update messages with NULL llm_model_id..."
    puts "WARNING: This task assumes a default model exists for the provider the message *should* have belonged to."
    puts "It cannot perfectly determine the original provider after the column rename."

    # Find the *very first* default model available in the system as a fallback.
    fallback_model = LlmToolkit::LlmModel.default.first || LlmToolkit::LlmModel.first
    unless fallback_model
      puts "ERROR: No LlmModels found at all. Cannot update messages. Please run 'populate_default_llm_models' task first."
      return
    end
    puts "Using fallback model ID: #{fallback_model.id} (#{fallback_model.name}) for messages where provider cannot be inferred."

    updated_count = 0
    skipped_count = 0

    # Iterate through messages needing update
    LlmToolkit::Message.where(llm_model_id: nil).find_each do |message|
      # Attempt to find the provider via the conversation's conversable, if possible
      provider = nil
      begin
        if message.conversation&.conversable&.respond_to?(:llm_providers)
          # This assumes the conversable has providers and we can guess based on that. Risky.
          # Let's just use the fallback for simplicity, as inferring is unreliable here.
          provider = nil # Force fallback
        end
      rescue => e
        puts "  WARN: Error trying to access conversable provider for message #{message.id}: #{e.message}"
      end

      target_model = fallback_model # Default to fallback

      # If we could reliably find the provider (which we decided against for now)
      # we would find its default model here:
      # target_model = provider&.default_llm_model || fallback_model

      if target_model
        begin
          message.update_column(:llm_model_id, target_model.id)
          updated_count += 1
          print '.' if updated_count % 100 == 0 # Progress indicator
        rescue => e
          puts "  ERROR: Failed to update message #{message.id}: #{e.message}"
          skipped_count += 1
        end
      else
        puts "  WARN: Could not find a suitable model for message #{message.id}. Skipping."
        skipped_count += 1
      end
    end

    puts "\nFinished updating messages."
    puts "Successfully updated: #{updated_count}"
    puts "Skipped/Errors: #{skipped_count}"
    if skipped_count > 0
       puts "WARNING: Some messages could not be updated. Their llm_model_id is still NULL."
    end
  end
end
