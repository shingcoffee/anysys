# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::CtaComponent, type: :component do
  it "takes Contact destinations and labels only from qualifying localized published nav records" do
    pages = %w[platform pricing about].map do |slug|
      WebsitePage.new(customer_id: 81_721_200, website_id: 7, slug: slug, title: "Saved #{slug}", published: true, nav_visible: true)
    end
    unpublished = pages.first.dup.tap { |record| record.published = false }
    hidden = pages.first.dup.tap { |record| record.nav_visible = false }
    foreign = pages.first.dup.tap { |record| record.customer_id = 42 }
    pages[1].published = false
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, customer_id: 81_721_200, variant: :contact_next_steps,
        nav_pages: [*pages, unpublished, hidden, foreign], props: { headline: "Next", body: "Saved copy", button_label: "Create", button_href: "/auth/sign_up" }))
      expect(html.css("a").map { |node| [node.at_css("h3").text, node["href"]] }).to eq([
        ["Saved platform", "/platform?locale=zh-CN"], ["Create", "/auth/sign_up?locale=zh-CN"]
      ])
      expect(html.at_css("h2")["class"].split).to include("text-slate-950")
      expect(html.at_css("p")["class"].split).to include("text-[18px]")
    end
  end

  it "renders a dark aurora closing and keeps an invalid CTA as text" do
    html = render_inline(described_class.new(theme: website_theme, variant: :closing,
      props: { headline: "Build <em>yours</em>", button_label: "Literal", button_href: "javascript:alert(1)" }))
    expect(html).to have_text("Build <em>yours</em>")
    expect(html).to have_text("Literal")
    expect(html.css("a, em")).to be_empty
    panel = html.at_css("h2").ancestors.find { |node| node["class"].to_s.include?("rounded-[2.5rem]") }
    expect(panel["class"]).to include("bg-slate-950", "isolate", "overflow-hidden")
    expect(html.at_css("h2")["class"].split).to include("text-white")
    expect(html.css("ul li").map { |node| node.text.strip }).to eq(I18n.t("website.home_site.trust"))
  end

  it "preserves saved navigation order and titles in three whole-card anchors with runtime descriptions in both locales" do
    pages = %w[pricing platform].map do |slug|
      WebsitePage.new(customer_id: 81_721_200, website_id: 7, slug: slug, title: "Owner #{slug}", published: true, nav_visible: true)
    end
    [:en, :'zh-CN'].each do |locale|
      I18n.with_locale(locale) do
        html = render_inline(described_class.new(theme: website_theme, customer_id: 81_721_200, variant: :contact_next_steps,
          nav_pages: pages, props: { headline: "Saved headline", body: "Saved body", button_label: "Owner signup", button_href: "/auth/sign_up" }))
        anchors = html.css("a")
        expect(anchors.map { |node| node.at_css("h3").text }).to eq(["Owner pricing", "Owner platform", "Owner signup"])
        expect(anchors.map { |node| node.at_css("p").text }).to eq(%w[pricing platform workspace].map { |route| I18n.t("website.home_site.contact.routes.#{route}") })
        suffix = locale == :en ? "" : "?locale=zh-CN"
        expect(anchors.map { |node| node["href"] }).to eq(["/pricing#{suffix}", "/platform#{suffix}", "/auth/sign_up#{suffix}"])
        expect(anchors.first.parent["class"]).to include("grid-cols-1", "md:grid-cols-2", "lg:grid-cols-3")
        expect(anchors.map { |node| node["class"] }).to all(include("min-w-0", "focus-visible:ring-2", "rounded-3xl"))
        expect(anchors.last["class"]).to include("bg-slate-950", "text-white")
        expect(html.css("a a, a button, form, input")).to be_empty
        expect(html.css("svg").all? { |node| node.ancestors.any? { |parent| parent["aria-hidden"] == "true" } || node["aria-hidden"] == "true" }).to be(true)
      end
    end
  end

  it "omits invalid or blank signup and empty route labels and lets the remaining cards reflow" do
    page = WebsitePage.new(customer_id: 81_721_200, slug: "platform", title: "Saved platform", published: true, nav_visible: true)
    blank = page.dup.tap { |record| record.slug = "pricing"; record.title = " " }
    [
      { button_label: "Unsafe signup", button_href: "javascript:alert(1)" },
      { button_label: " ", button_href: "/auth/sign_up" },
      { button_label: "Missing signup", button_href: "" }
    ].each do |props|
      html = render_inline(described_class.new(theme: website_theme, customer_id: 81_721_200, variant: :contact_next_steps,
        nav_pages: [blank, page], props: props))
      expect(html.css("a h3").map(&:text)).to eq(["Saved platform"])
      expect(html.at_css("a").parent["class"]).not_to include("md:grid-cols-2", "lg:grid-cols-3")
      expect(html).not_to have_text("Unsafe signup")
      expect(html).not_to have_text("Missing signup")
    end
  end

  it "keeps the closing saved action as a locale-preserving white pill above hidden geometry" do
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, variant: :closing,
        props: { headline: "Saved closing", body: "Saved body", button_label: "Saved signup", button_href: "/auth/sign_up" }))
      expect(html).to have_css('a[href="/auth/sign_up?locale=zh-CN"]', text: "Saved signup")
      expect(html.at_css("a")["class"]).to include("bg-white", "text-slate-950", "rounded-full", "focus-visible:ring-2")
      expect(html).to have_css('[aria-hidden="true"].pointer-events-none')
      expect(html.css("img, form, input, button")).to be_empty
    end
  end

  it "omits completely empty closing content and Contact content with no qualifying routes" do
    html = render_inline(described_class.new(theme: website_theme, variant: :closing, props: {}))
    expect(html.css("section, a")).to be_empty
    html = render_inline(described_class.new(theme: website_theme, variant: :contact_next_steps,
      props: { button_label: "Invalid action", button_href: "javascript:alert(1)" }))
    expect(html.css("section, a")).to be_empty
  end
end
