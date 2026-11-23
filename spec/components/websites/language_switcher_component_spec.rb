# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::LanguageSwitcherComponent, type: :component do
  def render_switcher(**options)
    render_inline(described_class.new(theme: website_theme, **options))
  end

  it "renders a compact professional dropdown with full accessible language names" do
    with_request_url("/81721200/site/about?locale=en") { render_switcher }

    expect(page).to have_css("details.group summary[aria-haspopup='menu'][aria-label='Language']")
    expect(page).to have_css("summary svg", count: 2)
    expect(page).to have_css("[role='menu'][aria-label='Language']", visible: :all)
    expect(page).to have_link("English", href: "/81721200/site/about?locale=en", visible: :all)
    expect(page).to have_link("简体中文", href: "/81721200/site/about?locale=zh-CN", visible: :all)
    expect(page).to have_css("a[role='menuitem'][aria-current='true'][lang='en'][hreflang='en']", count: 1, visible: :all)
    expect(page).to have_no_css("[data-controller], button, form")
  end

  it "replaces only locale while preserving nested filters, repeated values, and escaped query text" do
    with_request_url("/81721200/site/about?locale=en&preview=1&filter%5Bname%5D=A%26B&tags%5B%5D=one&tags%5B%5D=two") do
      render_switcher
    end

    href = page.find_link("简体中文", visible: :all)[:href]
    uri = URI.parse(href)
    expect(uri.path).to eq("/81721200/site/about")
    expect(Rack::Utils.parse_nested_query(uri.query)).to eq(
      "locale" => "zh-CN", "preview" => "1", "filter" => { "name" => "A&B" }, "tags" => %w[one two]
    )
  end

  it "localizes the control label, marks Chinese current, and uses the short trigger name" do
    I18n.with_locale(:"zh-CN") { render_switcher }

    expect(page).to have_css("summary[aria-label='语言']", text: "中文")
    expect(page).to have_css("[role='menu'][aria-label='语言']", visible: :all)
    expect(page).to have_css("a[aria-current='true'][lang='zh-CN']", text: "简体中文", visible: :all)
    expect(page).to have_link("English", visible: :all)
    expect(page).to have_css("a[aria-current]", count: 1, visible: :all)
  end

it "uses a ghost theme-matched trigger and visible focus rings in the light theme" do
  render_switcher(theme: website_theme("appearance" => "light"))

  summary = page.find("summary")
  expect(summary[:class]).to include("rounded-full", "text-neutral-600", "hover:bg-neutral-900/[0.04]", "focus-visible:ring-2")
  expect(page.find("[role='menu']", visible: :all)[:class]).to include("hidden", "group-open:block", "rounded-2xl")
  expect(page.find_link("English", visible: :all)[:class]).to include("bg-violet-50", "text-violet-800")
end

it "uses ghost theme-sensitive contrast in the dark theme" do
  render_switcher(theme: website_theme("appearance" => "dark"))

  summary = page.find("summary")
  expect(summary[:class]).to include("text-white/80", "hover:bg-white/10", "focus-visible:ring-white/60")
  expect(page.find_link("English", visible: :all)[:class]).to include("bg-white/10", "text-white")
end
end

