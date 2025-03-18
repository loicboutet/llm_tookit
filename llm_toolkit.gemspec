require_relative "lib/llm_toolkit/version"

Gem::Specification.new do |spec|
  spec.name        = "llm_toolkit"
  spec.version     = LlmToolkit::VERSION
  spec.authors     = ["Loïc Boutet"]
  spec.email       = ["loic@5000.dev"]
  spec.homepage    = "https://github.com/loicboutet/llm_toolkit"
  spec.summary     = "Rails engine for LLM integration with tool use capabilities"
  spec.description = "A Rails engine that provides integration with LLM providers and a flexible tool system for AI assistants"
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0.0"
  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "faraday-retry"
  spec.add_dependency "http", "~> 5.1" # Added for Jina API integration
end