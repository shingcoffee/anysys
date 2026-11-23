# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::IndexComponent, type: :component do
  it "uses a semantic numbered process rail and saved array order without rendering latent images or links" do
    html = render_inline(described_class.new(theme: website_theme, variant: :process, props: { heading: "Process", items: [
      { title: "Review", body: "<b>First</b>", image_url: "https://cdn.example/a.jpg", href: "about" }, { title: "Describe", body: "Second" }
    ] }))
    expect(html.css("ol > li h3").map(&:text)).to eq(%w[Review Describe])
    expect(html.css('li > span[aria-hidden="true"]').map(&:text)).to eq(%w[01 02])
    expect(html.css("img, a, b")).to be_empty
    expect(html).to have_text("<b>First</b>")
    expect(html.at_css("li p")["class"]).to include("text-[16px]")
    expect(html.at_css("h3")["class"]).to include("text-[22px]")
    expect(html.at_css("section")["class"]).to include("bg-slate-50")
    expect(html.at_css("ol")["class"]).to include("md:grid-cols-3")
    connector = html.at_css("ol").parent.at_css('div[aria-hidden="true"]')
    expect(connector["class"]).to include("hidden", "md:block", "bg-gradient-to-r")
    expect(html.css("li > span").map { |node| node["class"] }).to all(include("rounded-full", "bg-gradient-to-br"))
  end

  it "tiles six assistant cards as a bento with wide dark bookends and escaped authored text" do
    items = Array.new(6) { |index| { title: "Assistant #{index}", body: "Body <b>#{index}</b>" } }
    html = render_inline(described_class.new(theme: website_theme, variant: :assistant, page_role: :home,
                                             props: { kicker: "Anysys AI assistant", heading: "Builds while you talk", items: items }))
    expect(html.at_css("section")["class"]).to include("via-violet-50/60")
    expect(html.at_css("h2").text).to eq("Builds while you talk")
    grid = html.at_css("article").parent["class"]
    expect(grid).to include("grid-cols-1", "md:grid-cols-2", "lg:grid-cols-4")
    cards = html.css("article")
    expect(cards.map { |node| node.at_css("h3").text }).to eq(items.pluck(:title))
    expect(cards.map { |node| node["class"].include?("md:col-span-2") }).to eq([true, false, false, false, false, true])
    expect(cards.first["class"]).to include("bg-slate-950")
    expect(cards.last["class"]).to include("bg-gradient-to-br", "from-violet-600")
    expect([cards.first, cards.last].map { |node| node.at_css("h3")["class"] }).to all(include("text-white"))
    expect(cards[1].at_css("h3")["class"]).to include("text-slate-950")
    expect(cards.first.at_css('div[aria-hidden="true"]')).to be_present
    expect(html.css("article svg path").map { |node| node["d"] }.uniq.size).to eq(6)
    expect(html.css("article svg").map { |node| node["aria-hidden"] }).to all(eq("true"))
    expect(html).to have_text("Body <b>0</b>")
    expect(html.css("b, img, a, button")).to be_empty
  end

  it "falls back to an even assistant grid without wide cards when the count is not six" do
    html = render_inline(described_class.new(theme: website_theme, variant: :assistant, props: { items: [{ title: "One" }, { title: "Two" }, { title: "Three" }] }))
    expect(html.at_css("article").parent["class"]).to include("md:grid-cols-2", "lg:grid-cols-3")
    expect(html.css("article").map { |node| node["class"] }).to all(satisfy { |css| !css.include?("md:col-span-2") })
    expect(html.css("article").first["class"]).to include("bg-slate-950")
    expect(html.css("article").drop(1).map { |node| node["class"] }).to all(include("bg-white"))
  end

  it "keeps four capabilities in two columns with distinct gradient icons" do
    props = { items: Array.new(4) { |index| { title: "Capability #{index}" } } }
    html = render_inline(described_class.new(theme: website_theme, variant: :capabilities, page_role: :platform, props: props))
    grid = html.at_css("article").parent["class"]
    expect(grid).to include("md:grid-cols-2")
    expect(grid).not_to include("lg:grid-cols-3")
    expect(html.css("article svg").size).to eq(4)
    expect(html.css("article svg path").map { |node| node["d"] }.uniq.size).to eq(4)
    expect(html.css("article svg").map { |node| node["aria-hidden"] }).to all(eq("true"))
    tiles = html.css("article > div > span[aria-hidden='true']").map { |node| node["class"] }
    expect(tiles.uniq.size).to eq(4)
  end

  it "keeps Home capabilities in three-column cards with escaped authored text and no inferred media or actions" do
    html = render_inline(described_class.new(theme: website_theme, variant: :capabilities, props: { items: [
      { title: "Records", body: "Saved <b>copy</b>\nSecond line", href: "pricing", image_url: "https://cdn.example/photo.jpg" },
      {}, { title: "Forms" }, { title: "Website" }
    ] }))
    expect(html.css("article h3").map(&:text)).to eq(%w[Records Forms Website])
    expect(html.at_css("article").parent["class"]).to include("grid-cols-1", "md:grid-cols-2", "lg:grid-cols-3")
    expect(html.css("article").map { |node| node["class"] }).to all(include("rounded-3xl", "bg-white", "min-w-0"))
    expect(html.at_css("article p").text).to eq("Saved <b>copy</b>\nSecond line")
    expect(html.css("h1, b, img, a, button")).to be_empty
  end

  it "gives About principles quiet ordinal detail without changing their wording" do
    html = render_inline(described_class.new(theme: website_theme, variant: :principles, props: { items: [
      { title: "Expertise first", body: "Saved principle" }, { title: "Keep control", body: "Saved explanation" }
    ] }))
    expect(html.css("article h3").map(&:text)).to eq(["Expertise first", "Keep control"])
    expect(html.css('article span[aria-hidden="true"]').map(&:text).map(&:strip).reject(&:empty?)).to eq(%w[01 02])
    expect(html.css("svg").map { |node| node["focusable"] }).to all(eq("false"))
  end

  it "uses the pricing page role for a foundation band with check tiles while retaining saved items" do
    props = { heading: "Connected workspace", items: [{ title: "Records", body: "Authored records" }, { title: "Website" }, { title: "Services" }] }
    I18n.with_locale(:'zh-CN') do
      html = render_inline(described_class.new(theme: website_theme, variant: :capabilities, page_role: :pricing, props: props))
      expect(html.at_css("section")["class"]).to include("bg-slate-50")
      expect(html.css("article svg path").map { |node| node["d"] }.uniq).to eq(["m5 10.5 3.2 3L15 6.5"])
      expect(html.at_css("h2")["class"]).to include("tracking-normal")
      expect(html.css("article h3").map(&:text)).to eq(%w[Records Website Services])
      expect(html.css("ol, h1, a")).to be_empty
    end
    html = render_inline(described_class.new(theme: website_theme, variant: :capabilities, props: props))
    expect(html.at_css("section")["class"]).to include("bg-white")
  end

  it "does not create blank cards or numbered nodes for empty edited items" do
    %i[capabilities principles process].each do |variant|
      html = render_inline(described_class.new(theme: website_theme, variant: variant, props: { items: [nil, {}, { title: " ", body: "" }] }))
      expect(html.css("article, ol, svg, [aria-hidden]")).to be_empty
    end
  end
end
