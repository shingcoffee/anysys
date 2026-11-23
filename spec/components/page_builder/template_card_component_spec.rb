# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::TemplateCardComponent, type: :component do
  let(:template) do
    {
      key: "contact_detailed",
      name: "Detailed Contact",
      description: "Full contact form with phone, company, and department selector",
      category: "contact",
      theme_preset: "modern",
      preview_rows: [
        [{ type: :section, label: "Your Information" }],
        [{ type: :input, width: "half", label: "First Name" }, { type: :input, width: "half", label: "Last Name" }],
        [{ type: :input, width: "half", label: "Email" }, { type: :input, width: "half", label: "Phone" }],
        [{ type: :divider }],
        [{ type: :section, label: "Your Message" }],
        [{ type: :textarea, width: "full", label: "Message" }]
      ],
      layout: {
        default_width: "full",
        field_width_rules: { "text" => "half", "email" => "half" },
        sections: [],
        inject_elements: []
      }
    }
  end

  def render_card(tmpl = template, **opts)
    render_inline(described_class.new(template: tmpl, **opts))
  end

  it "renders the template name" do
    render_card
    expect(rendered_content).to have_text("Detailed Contact")
  end

  it "renders the template description" do
    render_card
    expect(rendered_content).to have_text("Full contact form with phone")
  end

  it "renders the theme badge" do
    render_card
    expect(rendered_content).to have_text("Modern")
  end

  it "has data-template-key attribute" do
    render_card
    expect(rendered_content).to have_css("[data-template-key='contact_detailed']")
  end

  it "has data-template-category attribute" do
    render_card
    expect(rendered_content).to have_css("[data-template-category='contact']")
  end

  it "has Stimulus target attribute" do
    render_card
    expect(rendered_content).to have_css("[data-template-selector-target='templateCard']")
  end

  it "has click action for Stimulus" do
    render_card
    expect(rendered_content).to have_css("[data-action*='click->template-selector#selectTemplate']")
  end

  it "renders preview rows as a mini form mockup" do
    render_card
    # Should render a white form container with preview elements
    expect(rendered_content).to have_css("div.bg-white.rounded-md")
  end

  it "renders section labels in preview" do
    render_card
    expect(rendered_content).to have_text("Your Information")
  end

  it "renders input placeholders in preview" do
    render_card
    expect(rendered_content).to have_text("First Name")
  end

  context "when selected" do
    it "applies selected border classes" do
      render_card(selected: true)
      expect(rendered_content).to have_css("[class*='border-indigo-500']")
    end

    it "shows checkmark icon" do
      render_card(selected: true)
      expect(rendered_content).to have_css("[data-checkmark]:not(.hidden)")
    end
  end

  context "when not selected" do
    it "applies default border classes" do
      render_card(selected: false)
      expect(rendered_content).to have_css("[class*='border-gray-200']")
    end

    it "hides checkmark icon" do
      render_card(selected: false)
      expect(rendered_content).to have_css("[data-checkmark].hidden")
    end
  end

  it "renders an SVG checkmark" do
    render_card
    expect(rendered_content).to have_css("svg")
  end

  describe "theme color methods" do
    it "returns correct accent class for indigo" do
      component = described_class.new(template: template)
      expect(component.accent_color_class).to eq("bg-indigo-500")
    end

    it "returns correct accent class for bold theme (rose)" do
      bold_template = template.merge(theme_preset: "bold")
      component = described_class.new(template: bold_template)
      expect(component.accent_color_class).to eq("bg-rose-500")
    end

    it "returns correct badge classes" do
      component = described_class.new(template: template)
      expect(component.theme_badge_classes).to include("bg-indigo-50")
    end
  end

  it "renders category badge on the thumbnail" do
    render_card
    expect(rendered_content).to have_css("[data-category-badge]")
  end

  it "renders category label in the info section" do
    render_card
    category_label = PageLayoutTemplates.categories.dig(template[:category], :label) || template[:category]
    expect(rendered_content).to have_text(category_label)
  end

  describe "theme color methods — all color branches" do
    # Preset names come from ThemeResolver::THEME_PRESETS keys
    {
      "modern"     => { accent_color: "bg-indigo-500",   accent_text: "text-indigo-600",   badge: "bg-indigo-50" },
      "minimalist" => { accent_color: "bg-slate-500",    accent_text: "text-slate-600",    badge: "bg-slate-50" },
      "bold"       => { accent_color: "bg-rose-500",     accent_text: "text-rose-600",     badge: "bg-rose-50" },
      "elegant"    => { accent_color: "bg-violet-500",   accent_text: "text-violet-600",   badge: "bg-violet-50" },
      "playful"    => { accent_color: "bg-emerald-500",  accent_text: "text-emerald-600",  badge: "bg-emerald-50" }
    }.each do |preset, expected|
      context "with theme_preset '#{preset}'" do
        subject { described_class.new(template: colored_template) }

        let(:colored_template) { template.merge(theme_preset: preset) }

        it "returns #{expected[:accent_color]} accent_color_class" do
          expect(subject.accent_color_class).to eq(expected[:accent_color])
        end

        it "returns #{expected[:accent_text]} accent_text_class" do
          expect(subject.accent_text_class).to eq(expected[:accent_text])
        end

        it "returns #{expected[:badge]} in theme_badge_classes" do
          expect(subject.theme_badge_classes).to include(expected[:badge])
        end
      end
    end

    context "with unknown theme_preset (no matching THEME_PRESETS entry)" do
      # When theme_preset is 'cosmic', ThemeResolver::THEME_PRESETS['cosmic'] is nil,
      # so theme_color returns 'indigo' via the `|| "indigo"` fallback.
      # The else branch in accent_color_class / accent_text_class / theme_badge_classes
      # is structurally unreachable: theme_color always returns one of the five named
      # colors or "indigo" (the THEME_DEFAULTS fallback). Documenting behavior only.
      subject { described_class.new(template: unknown_template) }

      let(:unknown_template) { template.merge(theme_preset: "cosmic") }

      it "falls back to bg-indigo-500 for accent_color_class (THEME_DEFAULTS fallback)" do
        expect(subject.accent_color_class).to eq("bg-indigo-500")
      end

      it "falls back to text-indigo-600 for accent_text_class" do
        expect(subject.accent_text_class).to eq("text-indigo-600")
      end

      it "falls back to bg-indigo-50 for theme_badge_classes (indigo, not gray)" do
        # theme_color returns 'indigo' from THEME_DEFAULTS, so the `when 'indigo'`
        # branch fires — bg-gray-50 (the else) is unreachable.
        expect(subject.theme_badge_classes).to include("bg-indigo-50")
      end
    end

    context "when theme_preset is nil (no preset in template)" do
      subject { described_class.new(template: no_preset_template) }

      let(:no_preset_template) { template.except(:theme_preset) }

      it "returns fallback color indigo for accent_color_class" do
        expect(subject.accent_color_class).to eq("bg-indigo-500")
      end
    end
  end

  describe "#category_group_label" do
    it "returns empty string when no group contains the category" do
      orphan_template = template.merge(category: "orphan_category")
      component = described_class.new(template: orphan_template)
      expect(component.category_group_label).to eq("")
    end
  end

  describe "#width_class" do
    let(:component) { described_class.new(template: template) }

    it "returns full width class" do
      expect(component.width_class("full")).to eq("w-full")
    end

    it "returns half width class" do
      expect(component.width_class("half")).to eq("w-[calc(50%-2px)]")
    end

    it "returns third width class" do
      expect(component.width_class("third")).to eq("w-[calc(33.33%-2px)]")
    end

    it "defaults to full width" do
      expect(component.width_class(nil)).to eq("w-full")
    end
  end
end
