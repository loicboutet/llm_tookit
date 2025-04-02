module LlmToolkit
  class Engine < ::Rails::Engine
    isolate_namespace LlmToolkit

    # Don't try to directly manipulate the Rails application's paths here
    # Instead, we'll use the built-in Rails engine functionality
    # to copy migrations via the Rake task

    initializer 'llm_toolkit.assets.precompile' do |app|
      app.config.assets.precompile += %w( llm_toolkit/application.css )
    end
    
    initializer 'llm_toolkit.require_dependencies' do
      begin
        require 'http'
      rescue LoadError => e
        Rails.logger.error "LlmToolkit: Failed to load required gem: #{e.message}"
        Rails.logger.error "Please ensure the 'http' gem is included in your application's Gemfile"
      end
    end

    # Load concerns and models, but only when not precompiling assets
    config.to_prepare do
      # Skip model loading during asset precompilation
      unless ENV['SECRET_KEY_BASE']&.start_with?('temporaryassetprecompilation') 
        # First load concerns
        Dir.glob(Engine.root.join("app", "models", "concerns", "**", "*.rb")).each do |c|
          require_dependency(c)
        end
        
        # Then load models
        Dir.glob(Engine.root.join("app", "models", "llm_toolkit", "*.rb")).each do |m|
          require_dependency(m)
        end
        
        # Load services
        Dir.glob(Engine.root.join("app", "services", "llm_toolkit", "*.rb")).each do |s|
          require_dependency(s)
        end
      end
    end
  end
end