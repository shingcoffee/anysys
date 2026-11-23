# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::CodeGenerators::DetailComponent, type: :component do
  let(:customer_id) { "81721200" }
  let(:path) { "element_types/process/utility/greet_generator" }
  let(:source_code) { "# frozen_string_literal: true\n\nclass GreetGenerator\nend\n" }
  let(:generator_class) do
    Class.new(CodeGenerators::BaseGenerator) do
      def self.name = "CodeGenerators::ElementTypes::Process::Utility::GreetGenerator"

      generator_metadata do
        description "Greets a person"
        category :utility
        version "1.2.0"
      end

      config_schema do
        input :person, required: true, example: "name"
        enum :tone, %w[plain loud], default: "plain"
        output :resultVar, default: "greeting"
      end

      def generate_body
        assign(:resultVar, read(:person))
      end
    end
  end

  def render_detail(klass = generator_class)
    render_inline(described_class.new(generator_class: klass, source_code: source_code, path: path, customer_id: customer_id))
  end

  describe "summary card" do
    subject(:rendered) { render_detail }

    it "uses the app-wide full-width admin container instead of its own max width" do
      root = rendered.at_css("div")
      expect(root["class"]).to include("w-full px-3 sm:px-4 lg:px-8", "py-8 lg:py-10")
      expect(root["class"]).not_to include("max-w-")
    end

    it "shows the generator name, version, kind, category and description" do
      expect(rendered.css("h1").text).to eq("greet")
      expect(rendered.text).to include("v1.2.0", "Step Action", "Utility", "Greets a person")
    end

    it "shows the file the generator lives in" do
      expect(rendered.text).to include("app/services/code_generators/element_types/process/utility/greet_generator.rb")
    end

    it "lists the ctx keys the sample step reads and writes" do
      expect(rendered.text).to include("name", "greeting")
    end

    it "lists aliases and dependencies only when there are any" do
      aliases = ->(html) { html.css("dt").find { |dt| dt.text == "Aliases" }.next_element.text.squish }
      expect(aliases.call(rendered)).to eq("—")
      expect(rendered.text).not_to include("Deps")

      klass = Class.new(generator_class) do
        def self.registered_names = %w[greet salute]
        def dependencies = ["Greeter"]
      end
      html = render_detail(klass)
      expect(aliases.call(html)).to eq("salute")
      expect(html.text).to include("Deps", "Greeter")
    end
  end

  describe "tabs" do
    subject(:rendered) { render_detail }

    it "renders Playground, Config schema and Source Code tabs with Playground selected" do
      tabs = rendered.css("[role='tab']")
      expect(tabs.map { |tab| tab.text.squish }).to match([/\APlayground/, /\AConfig schema 3/, /\ASource Code 4 lines/])
      expect(rendered.css("[role='tab'][aria-selected='true']").text).to include("Playground")
    end

    it "renders one panel per tab" do
      expect(rendered.css("[role='tabpanel']").size).to eq(3)
    end
  end

  describe "playground" do
    subject(:rendered) { render_detail }

    it "pre-fills the config with the sample input and points the runner at the test-run endpoint" do
      runner = rendered.at_css("[data-controller='generator-test-runner']")
      sample = JSON.parse(runner["data-generator-test-runner-sample-value"])

      expect(runner["data-generator-test-runner-url-value"])
        .to eq("/#{customer_id}/admin/maintenance/platform/code_generators/#{ERB::Util.url_encode(path)}/test_run")
      expect(sample).to eq("person" => "name", "tone" => "plain", "resultVar" => "greeting")
      expect(JSON.parse(rendered.at_css("textarea#generator-playground-config").text)).to eq(sample)
    end

    it "renders the sample run's generated step up front" do
      expect(rendered.css("[data-generator-test-runner-target='result']").text).to include("ctx[:greeting] =", "generated_step.rb")
    end

    it "shows the error instead of a result when the generator raises" do
      broken = Class.new(generator_class) do
        def generate_body = raise(ArgumentError, "boom")
      end
      expect(render_detail(broken).css("[data-generator-test-runner-target='result']").text).to include("boom")
    end
  end

  describe "schema and source panels" do
    subject(:rendered) { render_detail }

    it "describes every declared config field" do
      expect(rendered.css("tbody tr td:first-child").map { |cell| cell.text.squish }).to eq(%w[person tone resultVar])
    end

    it "links to the editor from the source panel" do
      expect(rendered.css("a[href='/#{customer_id}/admin/maintenance/platform/code_generators/#{ERB::Util.url_encode(path)}/edit']").text).to include("Edit source")
    end
  end
end
