# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::NavComponent, type: :component do
  let(:theme) { website_theme }
  let(:website) { website_record }
  let(:pages) do
    [
      website_page_record(title: "Home", slug: "", home: true),
      website_page_record(title: "About", slug: "about", home: false)
    ]
  end

  def render_nav(**overrides)
    render_inline(described_class.new(
      website: website,
      pages: pages,
      current_slug: "about",
      theme: theme,
      **overrides
    ))
  end

  it "renders the site name and page titles" do
    render_nav

    expect(page).to have_link("Acme Institute", href: "/12345678/?locale=en")
    expect(page).to have_link("About", href: "/12345678/about?locale=en")
    expect(page).to have_css("a[aria-current='page']", text: "About")
  end

  it "mounts website-nav with open/close labels and a mobile sheet" do
    render_nav

    expect(page).to have_css("[data-controller='website-nav']")
    expect(page).to have_css("[data-website-nav-target='trigger'][aria-expanded='false']")
    expect(page).to have_css("[data-website-nav-target='panel']")
    expect(page).to have_css("[data-website-nav-target='backdrop']")
    expect(page).to have_css("[data-action='click->website-nav#toggle']")
    expect(page).to have_css("[data-website-nav-target='trigger'][aria-label='Open menu']")
    expect(page).to have_text("Close menu")
  end

  it "renders the sheet beside the blurred header so fixed positioning targets the viewport" do
    render_nav

    expect(page).to have_css("header[class*='backdrop-blur']")
    expect(page).to have_no_css("header [data-website-nav-target='panel'], header [data-website-nav-target='backdrop']")
    expect(page).to have_css("[data-controller='website-nav'].contents > header + [data-website-nav-target='backdrop']")
  end

  it "labels the sheet dialog with the site name and gives it an icon close button" do
    render_nav

    expect(page).to have_css("[role='dialog'][aria-labelledby='website-nav-title']")
    expect(page).to have_css("#website-nav-title", text: "Acme Institute")
    expect(page).to have_css("[data-website-nav-target='panel'] button[data-action='click->website-nav#close'] svg + .sr-only", text: "Close menu")
    expect(page).to have_css("[data-website-nav-target='panel'] a[aria-current='page'][class*='text-site-lg']", text: "About")
    expect(page).to have_no_css("[data-website-nav-target='panel'] a[class*='text-site-base']")
  end

  it "keeps one professional language dropdown outside the scrolling nav and beside the hamburger" do
    render_nav

    expect(page).to have_css("header details summary[aria-label='Language']", count: 1)
    expect(page).to have_css("header details + button[data-website-nav-target='trigger']")
    expect(page).to have_no_css("nav details, [role='dialog'] details")
    expect(page).to have_no_css("[data-controller='user-menu'], form[action='/locale']")
    control = page.find("header details")
    expect(control[:class]).not_to include("hidden")
    expect(control.find(:xpath, "..")["class"]).not_to include("hidden", "overflow")
  end

  it "preserves Chinese on brand, desktop and mobile page navigation" do
    I18n.with_locale(:"zh-CN") { render_nav }

    expect(page).to have_link("Acme Institute", href: "/12345678/?locale=zh-CN")
    expect(page).to have_css("header nav a[href='/12345678/about?locale=zh-CN']")
    expect(page).to have_css("[role='dialog'] a[href='/12345678/about?locale=zh-CN']")
  end

  it "allows the brand to wrap instead of truncating beside the compact controls" do
    render_nav

    brand = page.find("header > div > div > a")
    expect(brand[:class]).to include("break-words", "min-w-0")
    expect(brand[:class]).not_to include("truncate")
  end

  it "exposes an sr-only tagline" do
    render_nav

    expect(page).to have_css(".sr-only", text: "Craft, research, and public programs")
  end

  it "uses a large-screen nav breakpoint so tablets keep the hamburger" do
    render_nav

    expect(page).to have_css("nav[class*='lg:flex']")
    expect(page).to have_css("button[data-website-nav-target='trigger'][class*='lg:hidden']")
    expect(page).to have_css("[data-website-nav-target='panel'][class*='lg:hidden']")
  end

  it "passes the current host and retains a mount prefix on clean navigation" do
    with_request_url("/12345678/site/about", host: "tenant.example.com") do
      vc_test_controller.request.script_name = "/app"
      allow(PageShortcuts::PublicPath).to receive(:website_home)
        .with(customer_id: 12345678, host: "tenant.example.com").and_return("/")
      allow(PageShortcuts::PublicPath).to receive(:website_slug)
        .with(slug: "about", customer_id: 12345678, host: "tenant.example.com").and_return("/about")
      render_nav
    end
    expect(page).to have_link("Acme Institute", href: "/app/?locale=en")
    expect(page).to have_link("About", href: "/app/about?locale=en")
  end
end
