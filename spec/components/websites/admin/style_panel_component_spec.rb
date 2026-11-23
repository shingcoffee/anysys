# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Admin::StylePanelComponent, type: :component do
  let(:theme) { Websites::Theme.new("accent" => "forest") }

  def targets(type, &filter)
    Websites::SectionStyles.targets_for(type).select(&filter)
  end

  def render_panel(type: "hero_split", key: "headline", styles: {}, label: "Headline", theme: self.theme, &block)
    selected = targets(type) { |target| target[:key] == key || target[:array] == key }
    render_inline(described_class.new(section_id: "sec_1", targets: selected, styles: styles, theme: theme, label: label), &block)
  end

  it "renders one hidden, labelled panel with reset and close actions" do
    render_panel

    panel = page.find("[data-style-panel]#website-style-sec_1-headline", visible: :all)
    expect(panel["hidden"]).not_to be_nil
    expect(panel["role"]).to eq("group")
    expect(panel["aria-label"]).to eq(I18n.t("website.admin.pages.style.trigger", target: "Headline"))
    expect(panel).to have_text(I18n.t("website.admin.pages.style.heading"))
    expect(panel).to have_css("button[data-action='click->website-builder#resetStyles:prevent']", text: I18n.t("website.admin.pages.style.reset"), visible: :all)
    expect(panel).to have_css("button[data-action='click->website-builder#toggleStyle'][aria-controls='website-style-sec_1-headline'][aria-label='#{I18n.t('common.actions.close')}']", visible: :all)
  end

  it "renders a single target's controls inline without an accordion" do
    render_panel

    expect(page).to have_css("div[data-style-target='headline'][data-style-kind='element']", visible: :all)
    expect(page).not_to have_css("details", visible: :all)
    %w[color font size weight italic align].each do |attribute|
      expect(page).to have_css("[data-style-target='headline'] [data-style-prop='#{attribute}']", visible: :all)
    end
    expect(page).to have_css("option[value='bold']", text: I18n.t("website.admin.pages.style.options.weights.bold"), visible: :all)
    expect(page).to have_css("label", text: I18n.t("website.admin.pages.style.options.aligns.center"), visible: :all)
    expect(page).to have_css("input[data-style-prop='color'][value='accent']", visible: :all)
  end

  it "collapses a list's targets into accordion rows with per-target dots" do
    render_panel(type: "feature_grid", key: "items", label: "Items", styles: { "items.title" => { "weight" => "bold" } })

    keys = page.all("details[data-style-target]", visible: :all).map { |el| el["data-style-target"] }
    expect(keys).to eq(%w[items items.title items.body])
    list = I18n.t(Websites::SectionFields::LABEL_KEYS.fetch("items"))
    expect(page).to have_css("details[data-style-target='items'] summary", text: I18n.t("website.admin.pages.style.targets.items", list: list), visible: :all)
    expect(page).to have_css("details[data-style-target='items.title'] summary", text: I18n.t(Websites::SectionFields::LABEL_KEYS.fetch("title")), visible: :all)
    expect(page).to have_css("details[data-style-target='items.title'] [data-style-dot]:not(.hidden)", visible: :all)
    expect(page).to have_css("details[data-style-target='items'] [data-style-dot].hidden", visible: :all)
    expect(page).to have_css("#website-style-sec_1-items", visible: :all)
  end

  it "renders section controls with palette-only backgrounds and any extra content first" do
    render_panel(key: "section", label: "Section") { "<p data-extra>Appearance</p>".html_safe }

    section = page.find("[data-style-target='section']", visible: :all)
    expect(section).to have_css("select#website_style_sec_1_section_heading_font[data-style-prop='heading_font']", visible: :all)
    expect(section).to have_css("input[type='radio'][data-style-prop='scale'][value='lg']", visible: :all)
    expect(section).to have_css("input[data-style-prop='background'][value='#0f172a']", visible: :all)
    expect(section).not_to have_css("input[data-style-prop='background'][value='accent']", visible: :all)
    expect(section).to have_css("[data-style-field='background'] legend", text: I18n.t("website.admin.pages.style.attributes.custom_background"), visible: :all)
    expect(page).to have_css("[data-style-panel] [data-extra]", visible: :all)
  end

  it "renders button shape and colors" do
    render_panel(key: "buttons", label: "Buttons")

    buttons = page.find("[data-style-target='buttons']", visible: :all)
    expect(buttons).to have_css("input[data-style-prop='shape'][value='pill']", visible: :all)
    expect(buttons).to have_css("[data-style-field='fill']", visible: :all)
    expect(buttons).to have_css("[data-style-field='text']", visible: :all)
  end

  it "checks stored values and reports edits" do
    styles = { "headline" => { "size" => "xl", "weight" => "bold" }, "section" => { "scale" => "" } }
    component = described_class.new(section_id: "sec_1", targets: targets("hero_split") { |t| t[:key] == "headline" }, styles: styles, theme: theme, label: "Headline")
    render_inline(component)

    expect(page).to have_css("input#website_style_sec_1_headline_size_xl[checked]", visible: :all)
    expect(page).to have_css("select[data-style-prop='weight'] option[value='bold'][selected]", visible: :all)
    expect(component).to be_edited

    section = described_class.new(section_id: "sec_1", targets: targets("hero_split") { |t| t[:key] == "section" }, styles: styles, theme: theme, label: "Section")
    expect(section).not_to be_edited
    render_inline(section)
    expect(page).to have_css("input#website_style_sec_1_section_scale_default[checked]", visible: :all)
  end

  it "builds a trigger that controls this panel" do
    component = described_class.new(section_id: "sec_1", targets: targets("hero_split") { |t| t[:key] == "headline" },
                                    styles: { "headline" => { "size" => "xl" } }, theme: theme, label: "Headline")
    trigger = component.trigger

    expect(trigger).to be_a(Websites::Admin::StyleTriggerComponent)
    expect(trigger.panel_id).to eq(component.panel_id)
    expect(trigger).to be_edited
  end

  it "ignores non-hash styles, skips empty targets and falls back to the default theme" do
    render_panel(styles: "nope", theme: nil)
    expect(page).to have_css("[data-style-panel]", visible: :all)
    expect(page).to have_css("input[data-style-prop='size'][value=''][checked]", visible: :all)

    expect(render_inline(described_class.new(section_id: "sec_1", targets: [], styles: {}, theme: theme, label: "x")).to_html).to be_blank
  end
end
