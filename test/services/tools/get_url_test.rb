require "test_helper"

module LlmToolkit
  class GetUrlTest < ActiveSupport::TestCase
    def setup
      @conversable = mock("Conversable")
    end

    test "definition has expected structure" do
      definition = LlmToolkit::Tools::GetUrl.definition
      
      assert_equal "get_url", definition[:name]
      assert_includes definition[:description], "URL"
      assert_equal "object", definition[:input_schema][:type]
      assert_includes definition[:input_schema][:required], "url"
    end

    test "validates URL format" do
      result = LlmToolkit::Tools::GetUrl.execute(
        conversable: @conversable,
        args: { "url" => "not-a-url" }
      )
      
      assert result[:error].present?
      assert_includes result[:error], "Invalid URL format"
    end

    test "handles service exceptions" do
      LlmToolkit::JinaService.any_instance.stubs(:fetch_url_content).raises(StandardError.new("API Error"))
      
      result = LlmToolkit::Tools::GetUrl.execute(
        conversable: @conversable,
        args: { "url" => "https://example.com" }
      )
      
      assert result[:error].present?
      assert_includes result[:error], "Error fetching URL"
    end
  end
end