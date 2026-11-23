# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::PerspectiveComponent, type: :component do
  let(:art) { "/site-images/anysys/anysys-local-desktop.svg" }
  let(:photo) { "/site-images/anysys/anysys-photo-desktop-night.webp" }

  it "renders repeated source photo once on a dark surface while retaining all saved future-scoped text" do
    html = render_inline(described_class.new(theme: website_theme, props: { kicker: "Coming soon", heading: "Local workspace",
      cards: Array.new(3) { |index| { title: "Benefit #{index}", body: "Upcoming #{index}", image_url: photo } } }))
    expect(html.css("img").map { |node| node["src"] }).to eq([photo])
    expect(html.at_css("img")["alt"]).to eq("Benefit 0")
    expect(html.css("h3").map { |node| node.text.strip }).to eq(["Benefit 0", "Benefit 1", "Benefit 2"])
    expect(html).to have_text("Coming soon")
    expect(html.css("a, button")).to be_empty
    expect(html.css("h3").map { |node| node["class"] }).to all(include("text-[18px]", "text-white"))
    expect(html.css("h3 + p").map { |node| node["class"] }).to all(include("text-[15px]"))
    expect(html.at_css("section")["class"]).to include("bg-slate-950")
    expect(html.css("h1")).to be_empty
  end

  it "keeps the localized overlay for bundled illustration art" do
    html = render_inline(described_class.new(theme: website_theme, props: { cards: [{ title: "Lead", image_url: art }] }))
    expect(html.css("svg[viewBox='0 0 1600 1000']").size).to eq(1)
  end

  it "retains distinct later-card custom HTTPS/upload art and stored alt, not other bundled art" do
    upload = "/81721200/site/media/custom-token"
    html = render_inline(described_class.new(theme: website_theme, customer_id: 81721200, props: { cards: [
      { title: "Lead", image_url: art }, { title: "Photo <b>one</b>", image_url: "https://cdn.example/photo.jpg", href: "about" },
      { title: "Upload", image_url: upload }, { title: "Repeat", image_url: "https://cdn.example/photo.jpg" },
      { title: "Other bundle", image_url: "/site-images/anysys/anysys-record-control.svg" }
    ] }))
    expect(html.css("img").map { |node| node["src"] }).to eq([art, "https://cdn.example/photo.jpg", upload])
    expect(html.css("figure img").map { |node| node["alt"] }).to eq(["Photo <b>one</b>", "Upload"])
    expect(html.css("figure img").map { |node| node["class"] }).to all(include("object-cover"))
    expect(html.css("b")).to be_empty
    expect(html).to have_css('h3 a[href="/about"]')
  end

  it "retains text without a placeholder when the lead is invalid" do
    html = render_inline(described_class.new(theme: website_theme, props: { cards: [{ title: "Text", body: "Saved", image_url: "invalid" }] }))
    expect(html).to have_text("Saved")
    expect(html.css("img")).to be_empty
    expect(html.css("svg").map { |node| node["aria-hidden"] }).to all(eq("true"))
  end

  it "preserves valid supplementary custom media when the lead is invalid and omits blank text cards" do
    html = render_inline(described_class.new(theme: website_theme, props: { kicker: "Coming soon", cards: [
      { image_url: "javascript:alert(1)" }, nil, {}, { image_url: "https://cdn.example/saved.jpg" },
      { title: "Keep local", body: "Future-scoped hosting", href: "javascript:alert(1)" },
      { image_url: "https://cdn.example/saved.jpg" }
    ] }))
    expect(html.css("img").map { |node| node["src"] }).to eq(["https://cdn.example/saved.jpg"])
    expect(html.css("h3").map { |node| node.text.strip }).to eq(["Keep local"])
    expect(html).to have_text("Coming soon")
    expect(html).to have_text("Future-scoped hosting")
    expect(html.css("a, button")).to be_empty
  end

  it "renders no invented benefit or placeholder for empty cards" do
    html = render_inline(described_class.new(theme: website_theme, props: { cards: [] }))
    expect(html.css("h1, h2, h3, p, img, figure, a, button")).to be_empty
  end
end
