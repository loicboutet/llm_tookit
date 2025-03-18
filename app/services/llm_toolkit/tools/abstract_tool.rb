module LlmToolkit
  module Tools
    class AbstractTool
      include LlmToolkit::CancellationCheck
      
      # This declaration only affects the class
      @subclasses = []

      class << self
        include LlmToolkit::CancellationCheck      
        
        # Define subclasses at the class << self level
        def subclasses
          @subclasses ||= []
        end

        def inherited(subclass)
          super
          # Make sure subclasses is initialized
          subclasses << subclass
        end
      end

      def self.execute(conversable:, args:, tool_use: nil)
        raise NotImplementedError, "#{self.name} does not implement execute method"
      end

      def self.definition
        raise NotImplementedError, "#{self.name} does not implement definition method"
      end

      def self.load_tools
        begin
          Dir[File.join(__dir__, '*.rb')].each do |file|
            begin
              require file
            rescue => e
              Rails.logger.error("Error loading tool file #{file}: #{e.message}")
            end
          end
        rescue => e
          Rails.logger.error("Error in load_tools: #{e.message}")
        end
      end

      def self.all_definitions
        # First load the built-in tools
        load_tools
        
        # Then try to load custom tools from the host app if available
        begin
          if defined?(Rails.application.config.paths) && 
             Rails.application.config.paths["app/services"].present?
            
            Array(Rails.application.config.paths["app/services"]).each do |path|
              tools_path = File.join(path, "llm_toolkit", "tools", "*.rb")
              Dir[tools_path].each do |file|
                begin
                  require file
                rescue => e
                  Rails.logger.error("Error loading custom tool file #{file}: #{e.message}")
                end
              end
            end
          end
        rescue => e
          Rails.logger.error("Error loading custom tools: #{e.message}")
        end
        
        # Ensure we have a valid subclasses array and extract definitions
        begin
          Rails.logger.info("Found #{subclasses.size} tool subclasses")
          
          definitions = subclasses.map do |subclass|
            begin
              definition = subclass.definition
              Rails.logger.info("Loaded definition for #{subclass.name}: #{definition[:name]}, #{definition[:description]}")
              definition
            rescue => e
              Rails.logger.error("Error loading tool definition for #{subclass.name}: #{e.message}")
              nil
            end
          end.compact
          
          Rails.logger.info("Returning #{definitions.size} tool definitions")
          definitions
        rescue => e
          Rails.logger.error("Error mapping tool definitions: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          [] # Return empty array on error
        end
      end

      def self.find_tool(name)
        begin
          load_tools
          
          found_tool = subclasses.find do |tool|
            begin
              tool_name = tool.definition[:name]
              Rails.logger.debug("Checking tool #{tool.name} with name #{tool_name} against #{name}")
              tool_name == name
            rescue => e
              Rails.logger.error("Error checking tool #{tool.name}: #{e.message}")
              false
            end
          end
          
          Rails.logger.info("Find tool #{name}: #{found_tool ? 'Found' : 'Not found'}")
          found_tool
        rescue => e
          Rails.logger.error("Error in find_tool: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          nil
        end
      end

      def to_hash
        self.class.definition
      end
    end
  end
end