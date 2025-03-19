module LlmToolkit
  class Engine < ::Rails::Engine
    isolate_namespace LlmToolkit

    # Enable Rails engine to copy migrations from this engine to the host application
    config.paths["db/migrate"].expanded.each do |expanded_path|
      Rails.application.config.paths["db/migrate"] << expanded_path
    end

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

    # Load concerns and models
    config.to_prepare do
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