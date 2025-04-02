module LlmToolkit
  # Conditionally define the ApplicationRecord class
  # Only define it if we're not in a precompilation environment
  if !ENV['SECRET_KEY_BASE']&.start_with?('temporaryassetprecompilation')
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  else
    # Define a dummy class for precompilation context
    class ApplicationRecord
      def self.abstract_class=(val)
        # No-op
      end
    end
  end
end