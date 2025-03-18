module LlmToolkit
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)
      
      def create_initializer
        template "initializer.rb", "config/initializers/llm_toolkit.rb"
      end
      
      def show_readme
        readme "README" if behavior == :invoke
      end
    end
  end
end