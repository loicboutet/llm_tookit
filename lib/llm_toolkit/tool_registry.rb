# frozen_string_literal: true

# Central registry for all available LlmToolkit tools.
# Tools register themselves here upon inheritance (both AbstractTool and ToolDSL).
module LlmToolkit
  module ToolRegistry
    @tools = Set.new # Use a Set to automatically handle duplicates
    @loaded = false
    @lock = Mutex.new

    class << self
      # Add a tool class to the registry.
      def register(tool_class)
        @lock.synchronize do
          @tools ||= Set.new
          @tools.add(tool_class)
        end
        # Optional logging:
        # Rails.logger.debug "[ToolRegistry] Registered: #{tool_class.name}" if defined?(Rails)
      end

      # Find a tool class by its definition name (e.g., 'list_files').
      def find_tool(name)
        load_all_tools unless @loaded
        (@tools || Set.new).find do |tool|
          begin
            # Ensure the tool class responds to :definition before calling it
            tool.respond_to?(:definition) && tool.definition[:name] == name
          rescue => e
            # Log error if definition retrieval fails for a specific tool
            Rails.logger.error "[ToolRegistry] Error checking tool #{tool.name}: #{e.message}" if defined?(Rails)
            false
          end
        end
      end

      # Ensure all tool files are loaded so they can register themselves.
      # This should only run once.
      def load_all_tools
        # Double-checked locking to prevent redundant loading in concurrent environments
        return if @loaded
        @lock.synchronize do
          return if @loaded # Check again inside lock

          Rails.logger.info "[ToolRegistry] First-time loading of all tools..." if defined?(Rails)

          # --- Load Engine Tools ---
          load_tool_files(File.expand_path('../../app/services/llm_toolkit/tools/*.rb', __dir__), "engine")

          # --- Load Host App Tools ---
          load_host_app_tools

          @loaded = true
          Rails.logger.info "[ToolRegistry] Tool loading complete. Registered tools: #{@tools.map(&:name).join(', ')}" if defined?(Rails) && @tools
        end
      end

      private

      # Helper to load tool files from a given path pattern.
      def load_tool_files(pattern, type)
        Dir[pattern].each do |file|
          begin
            require file # Loading the file triggers the `inherited` hook in AbstractTool/ToolDSL
          rescue => e
            Rails.logger.error "[ToolRegistry] Error loading #{type} tool file #{file}: #{e.message}" if defined?(Rails)
          end
        end
      rescue => e
        Rails.logger.error "[ToolRegistry] Error scanning for #{type} tools at #{pattern}: #{e.message}" if defined?(Rails)
      end

      # Helper to load tools specifically from the host application paths.
      def load_host_app_tools
        return unless defined?(Rails.application.config.paths) && Rails.application.config.paths["app/services"].present?

        Array(Rails.application.config.paths["app/services"]).each do |path|
          host_tools_pattern = File.join(path, "llm_toolkit", "tools", "*.rb")
          load_tool_files(host_tools_pattern, "custom")
        end
      rescue => e
        Rails.logger.error "[ToolRegistry] Error loading custom tools: #{e.message}" if defined?(Rails)
      end
    end
  end
end
