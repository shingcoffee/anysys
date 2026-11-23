# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodeBlockComponent, type: :component do
  let(:sample_code) { "class Test\n  def hello\n    puts 'Hello World'\n  end\nend" }

  describe "#initialize" do
    it "sets default values" do
      component = described_class.new(code: sample_code)
      aggregate_failures do
        expect(component.code).to eq(sample_code)
        expect(component.language).to eq("ruby")
        expect(component.filename).to eq("contract.rb")
      end
    end

    it "accepts custom values" do
      component = described_class.new(code: sample_code, language: "javascript", filename: "custom.js")
      aggregate_failures do
        expect(component.code).to eq(sample_code)
        expect(component.language).to eq("javascript")
        expect(component.filename).to eq("custom.js")
      end
    end
  end

  describe "#render?" do
    it "returns true when code is present" do
      expect(described_class.new(code: sample_code).render?).to be true
    end

    it "returns false when code is blank or nil" do
      aggregate_failures do
        expect(described_class.new(code: "").render?).to be false
        expect(described_class.new(code: nil).render?).to be false
      end
    end
  end

  describe "#line_count" do
    it "returns the number of lines in the code" do
      expect(described_class.new(code: sample_code).line_count).to eq(5)
    end

    it "returns 1 for single line code" do
      expect(described_class.new(code: "puts 'hello'").line_count).to eq(1)
    end
  end

  describe "#highlighted_code" do
    it "returns highlighted HTML for Ruby code" do
      highlighted = described_class.new(code: "def test; end").highlighted_code
      aggregate_failures do
        expect(highlighted).to be_html_safe
        expect(highlighted).to include("def")
      end
    end

    it "returns empty string for blank code" do
      expect(described_class.new(code: "").highlighted_code).to eq("")
    end
  end

  describe "#highlight_line" do
    subject(:component) { described_class.new(code: sample_code) }

    it "highlights a single line of code" do
      highlighted = component.highlight_line("def hello")
      aggregate_failures do
        expect(highlighted).to be_html_safe
        expect(highlighted).to include("def")
      end
    end

    it "returns empty string for blank or nil line" do
      aggregate_failures do
        expect(component.highlight_line("")).to eq("")
        expect(component.highlight_line(nil)).to eq("")
      end
    end
  end

  describe "default filename based on language" do
    {
      "ruby"       => "contract.rb",
      "javascript" => "script.js",
      "js"         => "script.js",
      "python"     => "script.py",
      "py"         => "script.py",
      "go"         => "code.go"
    }.each do |language, expected_filename|
      it "returns #{expected_filename} for language '#{language}'" do
        expect(described_class.new(code: sample_code, language: language).filename).to eq(expected_filename)
      end
    end
  end

  # Render-depth coverage: exercise the template, not just the class methods.
  describe "rendered output", type: :component do
    it "renders the filename, syntax-highlighted code, line numbers, and copy affordance" do
      rendered = render_inline(described_class.new(code: sample_code, filename: "widget.rb"))

      aggregate_failures do
        expect(rendered).to have_css("span", text: "widget.rb")
        expect(rendered).to have_css("code.highlight")
        expect(rendered).to have_css("code.highlight span")   # Rouge emitted token spans
        expect(rendered.css("code.highlight").text).to include("class") # source rendered
        expect(rendered).to have_css("button[data-controller='copy-code']")
        expect(rendered).to have_text("5 lines")
        # one line-number cell per source line
        expect(rendered.css("div.leading-6").map(&:text)).to include("1", "5")
      end
    end

    it "renders nothing when code is blank (render? is false)" do
      rendered = render_inline(described_class.new(code: ""))
      expect(rendered.to_html.strip).to eq("")
    end
  end
end
