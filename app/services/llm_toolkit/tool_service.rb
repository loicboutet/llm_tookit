module LlmToolkit
  class ToolService
    def self.build_tool_definitions(tools)
      # Debug output to understand what's being passed
      Rails.logger.info "Building tool definitions for: #{tools.map(&:name).join(', ')}"
      
      # Get definitions and log them
      defs = tools.map do |tool|
        definition = tool.definition
        Rails.logger.info "Tool definition for #{tool.name}: #{definition.inspect}"
        definition
      end
      
      # Return the definitions
      defs
    end
    
    def self.tool_definitions
      # Simply return an empty array when no tools are specified
      # instead of automatically collecting all tool definitions
      []
    end

    def self.execute_tool(tool_use)
      begin
        conversable = tool_use.message.conversation.conversable
        tool_class = LlmToolkit::Tools::AbstractTool.find_tool(tool_use.name)

        if tool_class
          # Ensure input is always a valid hash
          input = if tool_use.input.nil? || tool_use.input == ""
                    {}
                  elsif tool_use.input.is_a?(String)
                    begin
                      JSON.parse(tool_use.input)
                    rescue
                      {}
                    end
                  else
                    tool_use.input
                  end
                  
          result = tool_class.execute(conversable: conversable, args: input, tool_use: tool_use)
          
          # Check if the tool is requesting asynchronous handling
          if result.is_a?(Hash) && result[:state] == "asynchronous_result"
            Rails.logger.info("Tool #{tool_use.name} requested asynchronous result handling")
            # The tool_use will be flagged as waiting for an async result
            tool_use.update(status: :waiting)
            # Create initial result but mark it as pending
            create_tool_result(tool_use, result.merge(is_pending: true))
            # Signal to the caller that we're waiting for an async result
            return { asynchronous: true, tool_use_id: tool_use.id }
          end
        else
          result = { error: "Unknown tool: #{tool_use.name}" }
        end

        create_tool_result(tool_use, result)
      rescue => e
        Rails.logger.error("Error executing tool #{tool_use.name}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        create_tool_result(tool_use, { error: "Error executing tool: #{e.message}" })
      end
    end

    private

    def self.create_tool_result(tool_use, result)
      # Ensure result is a hash with expected keys
      result ||= {}
      
      # Check if this is a pending asynchronous result
      is_pending = result.delete(:is_pending) || false
      
      tool_use.create_tool_result!(
        message: tool_use.message,
        content: result[:result] || result[:error] || "No result provided",
        is_error: result.key?(:error),
        diff: result[:diff],
        pending: is_pending
      )
    rescue => e
      Rails.logger.error("Error creating tool result: #{e.message}")
      
      # Try to create a fallback result
      begin
        tool_use.create_tool_result!(
          message: tool_use.message,
          content: "Error processing tool result: #{e.message}",
          is_error: true,
          diff: nil
        )
      rescue => inner_e
        Rails.logger.error("Failed to create fallback tool result: #{inner_e.message}")
      end
    end
  end
end