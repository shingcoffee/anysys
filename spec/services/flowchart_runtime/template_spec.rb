# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Template do
  describe ".render" do
    it "renders liquid templates with variables" do
      result = described_class.render("Hello {{ name }}", { "name" => "World" }, engine: :liquid)
      expect(result).to eq("Hello World")
    end

    it "accepts string engine names" do
      expect(described_class.render("Hi {{ x }}", { "x" => "!" }, engine: "liquid")).to eq("Hi !")
    end

    it "raises Error for unsupported engines" do
      expect { described_class.render("x", {}, engine: :haml) }
        .to raise_error(described_class::Error, /unsupported engine/)
    end

    it "raises Error for invalid liquid syntax" do
      expect { described_class.render("{% if %}", {}, engine: :liquid) }
        .to raise_error(described_class::Error)
    end

    it "uses Liquid render! for strict variables" do
      parsed = Liquid::Template.parse("{{ name }}")
      allow(Liquid::Template).to receive(:parse).and_return(parsed)
      expect(parsed).to receive(:render!).with({ "name" => "Ada" }, strict_variables: true).and_call_original

      described_class.render("{{ name }}", { name: "Ada" }, engine: :liquid, strict_variables: true)
    end

    it "normalizes undefined strict variables to Template::Error" do
      expect {
        described_class.render("Hello {{ missing }}", {}, strict_variables: true)
      }.to raise_error(described_class::Error, /missing/)
    end

    it "rejects unsupported engines" do
      expect { described_class.render("x", {}, engine: :ruby) }
        .to raise_error(described_class::Error, /unsupported engine/)
    end
  end

  describe ".interpolate" do
    it "reads placeholders from ctx when variables are empty" do
      expect(described_class.interpolate({ name: "Ada" }, "Hello {{ name }}")).to eq("Hello Ada")
    end

    it "lets explicit variables override ctx" do
      expect(described_class.interpolate({ name: "ignored" }, "Hello {{ name }}", variables: { "name" => "Ada" }))
        .to eq("Hello Ada")
    end

    it "escapes interpolated values for html output and trims the result" do
      expect(described_class.interpolate({ name: "<b>Ada</b>" }, "  <p>{{ name }}</p>  ",
                                         output_format: "html", trim_whitespace: true))
        .to eq("<p>&lt;b&gt;Ada&lt;/b&gt;</p>")
    end
  end
end
