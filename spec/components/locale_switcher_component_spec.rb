# frozen_string_literal: true

require "rails_helper"

RSpec.describe LocaleSwitcherComponent, type: :component do
  def render_with(current: :en, align: :right)
    render_inline(described_class.new(current: current, align: align))
  end

  it "renders one PATCH /locale form per available locale" do
    rendered = render_with
    forms = rendered.css("form[action='/locale']")
    expect(forms.size).to eq(I18n.available_locales.size)
    expect(forms.css("input[name='_method'][value='patch']")).to be_present
    hidden = rendered.css("input[name='locale']").map { |i| i.attr("value") }
    expect(hidden).to match_array(I18n.available_locales.map(&:to_s))
  end

  it "shows each language by its endonym" do
    rendered = render_with
    expect(rendered.text).to include("English")
    expect(rendered.text).to include("简体中文")
  end

  it "marks the current locale with a check icon" do
    rendered = render_with(current: :"zh-CN")
    zh_button = rendered.css("form[action='/locale']").find do |f|
      f.css("input[name='locale']").first&.attr("value") == "zh-CN"
    end
    en_button = rendered.css("form[action='/locale']").find do |f|
      f.css("input[name='locale']").first&.attr("value") == "en"
    end
    expect(zh_button.css("svg").size).to be > en_button.css("svg").size
  end

  it "aligns the panel right by default and left when requested" do
    expect(render_with(align: :right).css(".right-0")).to be_present
    expect(render_with(align: :left).css(".left-0")).to be_present
  end

  it "uses inverted marketing classes on a dark public chrome" do
    html = render_inline(described_class.new(current: :en, inverted: true))
    expect(html.to_html).to include("hover:bg-white/10")
    expect(html.to_html).to include("bg-neutral-950")
    expect(html.to_html).not_to include("dropdown-panel")
  end

  it "hides the language name below sm by default and keeps it when labelled" do
    compact = render_inline(described_class.new(current: :en))
    expect(compact.css("button[data-user-menu-target='trigger'] span.hidden.sm\\:inline").text).to eq("English")

    labelled = render_inline(described_class.new(current: :en, labelled: true))
    trigger = labelled.css("button[data-user-menu-target='trigger']")
    expect(trigger.css("span.inline").text).to eq("English")
    expect(trigger.css(".hidden")).to be_empty
  end

  it "falls back to the raw code as a display name for an unknown locale" do
    component = described_class.new(current: :en)
    expect(component.display_name(:fr)).to eq("fr")
  end
end
