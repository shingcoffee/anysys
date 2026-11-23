# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::BaseElementComponent, type: :component do
  # Exercise the protected helpers through a minimal subclass, the way the
  # 16 layout element components consume them.
  let(:probe_class) do
    Class.new(described_class) do
      def self.name = "FormFields::ProbeElementComponent"

      def call
        content_tag :div, nil, class: [
          neutral(:muted_text),
          accent[:text],
          palette[:bg],
          alignment_class(probe_alignment)
        ].join(" ")
      end

      attr_accessor :probe_alignment
    end
  end

  def render_probe(theme: {}, alignment: "left")
    component = probe_class.new(theme: theme)
    component.probe_alignment = alignment
    render_inline(component)
  end

  it "defaults theme to an empty hash and resolves the default palette" do
    rendered = render_probe
    expect(rendered.css("div").first["class"]).to include("bg-indigo-600")
  end

  it "resolves palette and accent from the given theme" do
    rendered = render_probe(theme: { "primary_color" => "rose", "accent_color" => "rose" })
    classes = rendered.css("div").first["class"]
    expect(classes).to include("bg-rose-600")
    expect(classes).to include("text-rose-600")
  end

  it "exposes ELEMENT_NEUTRALS values via neutral()" do
    rendered = render_probe
    expect(rendered.css("div").first["class"]).to include("text-gray-500")
  end

  it "raises KeyError for an unknown neutral key" do
    component = probe_class.new
    expect { component.send(:neutral, :nonexistent) }.to raise_error(KeyError)
  end

  describe "#alignment_class" do
    it "maps center and right to text alignment classes" do
      expect(render_probe(alignment: "center").css("div").first["class"]).to include("text-center")
      expect(render_probe(alignment: "right").css("div").first["class"]).to include("text-right")
    end

    it "falls back to text-left for unknown or missing alignment" do
      expect(render_probe(alignment: "diagonal").css("div").first["class"]).to include("text-left")
      expect(render_probe(alignment: nil).css("div").first["class"]).to include("text-left")
    end
  end
end
