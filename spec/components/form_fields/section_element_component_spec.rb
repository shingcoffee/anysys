# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormFields::SectionElementComponent, type: :component do
  def render_section(**overrides)
    args = { title: "Section Title" }.merge(overrides)
    render_inline(described_class.new(**args))
  end

  describe "default variant (no preset theme)" do
    it "renders a legend with default styling" do
      render_section
      expect(page).to have_css("legend.text-lg.font-semibold.text-gray-900", text: "Section Title")
    end

    it "renders a bottom border on the legend (no preset — falls back to border-b)" do
      render_section
      expect(page).to have_css("legend.border-b.border-gray-100")
    end

    it "does not apply linked variant styles" do
      rendered = render_section
      fieldset = rendered.css("fieldset").first
      legend = rendered.css("legend").first
      expect(fieldset["class"]).not_to include("border-l-2")
      expect(legend["class"]).not_to include("border-l-2")
      expect(legend["class"]).not_to include("pl-4")
    end

    it "fieldset carries the section spacing top and bottom margins" do
      rendered = render_section
      fieldset = rendered.css("fieldset").first
      # Default theme (no field_spacing key) → normal spacing → mt-6 mb-2.5
      expect(fieldset["class"]).to include("mt-6")
      expect(fieldset["class"]).to include("mb-2.5")
    end
  end

  describe "default variant — with preset themes" do
    it "modern preset: legend has left border accent (border-indigo-300)" do
      rendered = render_section(theme: ThemeResolver::THEME_PRESETS["modern"].dup)
      legend = rendered.css("legend").first
      expect(legend["class"]).to include("border-l-2")
      expect(legend["class"]).to include("border-indigo-300")
      # Accent must live on the legend — fieldset border-left paints below the
      # legend slot and reads as a mid-title misaligned bar.
      expect(rendered.css("fieldset").first["class"]).not_to include("border-l-2")
    end

    it "modern preset: legend does NOT have bottom border (left border replaces it)" do
      rendered = render_section(theme: ThemeResolver::THEME_PRESETS["modern"].dup)
      legend = rendered.css("legend").first
      expect(legend["class"]).not_to include("border-b")
      expect(legend["class"]).not_to include("pb-1.5")
    end

    it "minimalist preset: legend has no left border" do
      rendered = render_section(theme: ThemeResolver::THEME_PRESETS["minimalist"].dup)
      legend = rendered.css("legend").first
      expect(legend["class"]).not_to include("border-l-2")
    end

    it "minimalist preset: legend has uppercase style" do
      render_section(theme: ThemeResolver::THEME_PRESETS["minimalist"].dup)
      expect(page).to have_css("legend.uppercase.tracking-widest")
    end

    it "bold preset: legend has rose left border" do
      rendered = render_section(theme: ThemeResolver::THEME_PRESETS["bold"].dup)
      legend = rendered.css("legend").first
      expect(legend["class"]).to include("border-rose-400")
    end

    it "elegant preset: fieldset has top/bottom margin but no left border" do
      rendered = render_section(theme: ThemeResolver::THEME_PRESETS["elegant"].dup)
      fieldset = rendered.css("fieldset").first
      legend = rendered.css("legend").first
      expect(fieldset["class"]).to include("mt-8")
      expect(fieldset["class"]).not_to include("border-l-2")
      expect(legend["class"]).not_to include("border-l-2")
    end

    it "elegant preset: legend has font-serif and violet text" do
      render_section(theme: ThemeResolver::THEME_PRESETS["elegant"].dup)
      expect(page).to have_css("legend.font-serif")
    end

    it "relaxed-spacing presets use mt-8 on fieldset" do
      rendered = render_section(theme: ThemeResolver::THEME_PRESETS["showcase"].dup)
      fieldset = rendered.css("fieldset").first
      expect(fieldset["class"]).to include("mt-8")
    end
  end

  describe "linked variant" do
    it "renders a legend with linked styling" do
      render_section(variant: "linked")
      expect(page).to have_css("legend.text-xs.uppercase", text: "Section Title")
    end

    it "applies left border accent to the legend (not the fieldset)" do
      rendered = render_section(variant: "linked")
      legend = rendered.css("legend").first
      expect(legend["class"]).to include("border-l-2")
      expect(legend["class"]).to include("pl-4")
      expect(rendered.css("fieldset").first["class"]).not_to include("border-l-2")
    end

    it "applies accent color to the legend border" do
      rendered = render_section(variant: "linked")
      legend = rendered.css("legend").first
      # Default theme is indigo; border_accent = border-indigo-200
      expect(legend["class"]).to include("border-indigo-200")
    end

    it "applies accent color to the legend text" do
      render_section(variant: "linked")
      # Default theme is indigo; text = text-indigo-600
      expect(page).to have_css("legend.text-indigo-600")
    end

    it "does not render a bottom border divider" do
      render_section(variant: "linked")
      expect(page).not_to have_css("div.border-t")
    end
  end

  describe "description" do
    it "renders the description when present" do
      render_section(description: "This is a description")
      expect(page).to have_css("p.text-sm.text-gray-500", text: "This is a description")
    end

    it "does not render a description element when not provided" do
      render_section(description: nil)
      expect(page).not_to have_css("p.text-sm")
    end

    it "renders description in linked variant" do
      render_section(variant: "linked", description: "Bridge context")
      expect(page).to have_css("p.text-sm.text-gray-500", text: "Bridge context")
    end
  end

  describe "variant coercion" do
    it "treats unknown variant as default" do
      rendered = render_section(variant: "unknown")
      legend = rendered.css("legend").first
      expect(legend["class"]).to include("text-lg")
      expect(legend["class"]).not_to include("uppercase")
    end

    it "treats nil variant as default" do
      render_section(variant: nil)
      expect(page).to have_css("legend.text-lg.font-semibold.text-gray-900")
    end
  end

  describe "theme parameter" do
    it "accepts a theme hash without raising" do
      expect { render_section(theme: { "primary_color" => "rose" }) }.not_to raise_error
    end

    it "applies theme-derived border accent on linked variant" do
      rendered = render_section(variant: "linked", theme: { "primary_color" => "rose" })
      legend = rendered.css("legend").first
      expect(legend["class"]).to include("border-rose-200")
    end

    it "defaults to indigo border accent when theme is {}" do
      rendered = render_section(variant: "linked", theme: {})
      legend = rendered.css("legend").first
      expect(legend["class"]).to include("border-indigo-200")
    end

    it "applies rose legend text color on linked variant with rose primary_color theme" do
      render_section(variant: "linked", theme: { "primary_color" => "rose" })
      expect(page).to have_css("legend.text-rose-600")
    end

    it "does not apply rose border accent for default variant (non-preset custom theme)" do
      rendered = render_section(variant: nil, theme: { "primary_color" => "rose" })
      legend = rendered.css("legend").first
      # A custom theme (non-preset) → resolve_section_border returns "" → no border-l-2
      expect(legend["class"]).not_to include("border-l-2")
    end
  end
end
