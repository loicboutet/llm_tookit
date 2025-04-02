module LlmToolkit
  # Conditionally define the ApplicationRecord class
  # Only define it if we're not in a precompilation environment
  if !ENV['ASSET_PRECOMPILATION_MODE'] == 'true'
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  else
    # Define a dummy class for precompilation context
    class ApplicationRecord
      def self.abstract_class=(val)
        # No-op
      end
      
      # Add other commonly used ActiveRecord class methods as no-ops
      def self.belongs_to(*args); end
      def self.has_many(*args); end
      def self.validates(*args); end
      def self.validate(*args); end
      def self.before_save(*args); end
      def self.after_create(*args); end
      def self.after_update(*args); end
      def self.after_destroy(*args); end
      def self.has_one(*args); end
      def self.scope(*args); end
      def self.enum(*args); end
      def self.attribute(*args); end
      def self.broadcasts_refreshes(*args); end
    end
  end
end