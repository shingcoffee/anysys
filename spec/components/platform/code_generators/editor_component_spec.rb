# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::EditorComponent, type: :component do
  let(:customer_id) { "81721200" }
  let(:path) { "element_types/process/utility/greet_generator" }
  let(:generator_url) { "/#{customer_id}/admin/maintenance/platform/code_generators/#{ERB::Util.url_encode(path)}" }
  let(:generator_class) do
    Class.new(CodeGenerators::BaseGenerator) do
      def self.name = "CodeGenerators::ElementTypes::Process::Utility::GreetGenerator"

      generator_metadata do
        version "1.2.0"
      end
    end
  end

  def render_editor(errors: [])
    render_inline(described_class.new(
      generator_class: generator_class, path: path, customer_id: customer_id,
      methods_body: "def generate_body\n  \"true\"\nend", errors: errors
    ))
  end

  it "patches the class body to the generator and validates it through the validation endpoint" do
    form = render_editor.at_css("form[data-controller='code-editor']")

    expect(form["action"]).to eq(generator_url)
    expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
    expect(form["data-code-editor-validate-url-value"]).to eq("#{generator_url}/validation")
    expect(form["data-code-editor-validating-label-value"]).to eq("Validating...")
    expect(form["data-code-editor-all-checks-passed-label-value"]).to eq("All checks passed")
  end

  it "edits the class body in the source editor under the class declaration" do
    html = render_editor

    expect(html.text).to include("class CodeGenerators::ElementTypes::Process::Utility::GreetGenerator < CodeGenerators::BaseGenerator")
    expect(html.at_css("textarea[name='methods_body']").text).to include("def generate_body")
  end

  it "offers validate, cancel and save, and links back to the generator" do
    html = render_editor

    expect(html.at_css("button[data-action='code-editor#validate']").text).to include("Validate")
    expect(html.css("a[href='#{generator_url}']").map { |link| link.text.squish }).to include("Cancel")
    expect(html.at_css("button[type='submit']").text).to include("Save Changes")
    expect(html.text).to include("greet", "v1.2.0", "Ctrl/⌘ + S to save")
  end

  it "shows the helper reference beside the editor" do
    expect(render_editor.css("aside").text).to include("Helpers", "Schema roles")
  end

  it "shows save errors" do
    expect(render_editor(errors: ["SyntaxError on line 3"]).text).to include("SyntaxError on line 3")
  end
end
