# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::ProgressBarElementComponent, type: :component do
  it "renders progress bar with value" do
    render_inline(described_class.new(label: "Progress", progress_value: 75))
    expect(page).to have_text("75%")
    expect(page).to have_css("div[style='width: 75%']")
  end

  it "renders label when provided" do
    render_inline(described_class.new(label: "Upload", progress_value: 50))
    expect(page).to have_text("Upload")
  end

  it "does not render label when empty" do
    render_inline(described_class.new(progress_value: 50))
    expect(page).not_to have_css("span.font-medium")
  end

  it "clamps value to 0-100 range" do
    component = described_class.new(progress_value: 150)
    expect(component.progress_value).to eq(100)

    component2 = described_class.new(progress_value: -10)
    expect(component2.progress_value).to eq(0)
  end

  it "defaults to indigo color" do
    render_inline(described_class.new(progress_value: 50))
    expect(page).to have_css("div.bg-indigo-600")
  end

  it "renders green color" do
    render_inline(described_class.new(progress_value: 50, progress_color: "green"))
    expect(page).to have_css("div.bg-green-600")
  end

  it "renders blue color" do
    render_inline(described_class.new(progress_value: 50, progress_color: "blue"))
    expect(page).to have_css("div.bg-blue-600")
  end

  it "renders red color" do
    render_inline(described_class.new(progress_value: 50, progress_color: "red"))
    expect(page).to have_css("div.bg-red-600")
  end

  it "defaults to 0 progress" do
    component = described_class.new
    expect(component.progress_value).to eq(0)
  end

  # Task C — e. ProgressBarElementComponent: progress_color fallback behavior

  describe "progress_color fallback to theme primary palette" do
    context "when progress_color is unknown" do
      it "falls back to the theme primary palette bg (teal → bg-teal-600)" do
        component = described_class.new(progress_value: 50, progress_color: "unknown_color",
                                        theme: { "primary_color" => "teal" })
        expect(component.color_class).to eq("bg-teal-600")
      end

      it "renders the theme primary bg class in HTML" do
        render_inline(described_class.new(progress_value: 50, progress_color: "unknown_color",
                                          theme: { "primary_color" => "teal" }))
        expect(page).to have_css("div.bg-teal-600")
      end
    end

    context "when progress_color is absent (uses default param value 'indigo')" do
      it "uses indigo bg (the known default) when no theme is given" do
        component = described_class.new(progress_value: 50)
        expect(component.color_class).to eq("bg-indigo-600")
      end
    end

    context "when progress_color is known 'green'" do
      it "uses bg-green-600 regardless of theme primary" do
        component = described_class.new(progress_value: 50, progress_color: "green",
                                        theme: { "primary_color" => "rose" })
        expect(component.color_class).to eq("bg-green-600")
      end

      it "renders bg-green-600 in HTML even with rose theme" do
        render_inline(described_class.new(progress_value: 50, progress_color: "green",
                                          theme: { "primary_color" => "rose" }))
        expect(page).to have_css("div.bg-green-600")
        expect(page).not_to have_css("div.bg-rose-600")
      end
    end

    context "when progress_color is unknown and theme primary_color is also unknown" do
      it "falls back through palette to the COLORS default (indigo via palette fallback)" do
        component = described_class.new(progress_value: 50, progress_color: "holographic",
                                        theme: { "primary_color" => "nonexistent_hue" })
        # color_palette falls back to indigo for unknown primary_color
        expect(component.color_class).to eq("bg-indigo-600")
      end
    end

    context "when progress_color is unknown and theme is {}" do
      it "falls back to theme primary default (indigo → bg-indigo-600)" do
        component = described_class.new(progress_value: 50, progress_color: "holographic", theme: {})
        # THEME_DEFAULTS primary_color = 'indigo', color_palette({})[:bg] = 'bg-indigo-600'
        expect(component.color_class).to eq("bg-indigo-600")
      end
    end
  end
end
