# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::MarqueeComponent, type: :component do
  it "renders saved names once for assistive technology and a hidden duplicate run for the seamless loop" do
    html = render_inline(described_class.new(theme: website_theme, props: { heading: "Made for", items: [
      { name: "Studios <b>&</b> clubs" }, { name: "Nonprofits" }, { name: " " }, {}
    ] }))
    expect(html.at_css("h2").text).to eq("Made for")
    runs = html.css("ul")
    expect(runs.size).to eq(2)
    expect(runs.first["aria-hidden"]).to be_nil
    expect(runs.last["aria-hidden"]).to eq("true")
    expect(runs.last["class"]).to include("motion-reduce:hidden")
    expect(runs.first.css("li").map { |node| node.text.strip }).to eq(["Studios <b>&</b> clubs", "Nonprofits"])
    expect(html.css("b")).to be_empty
    track = runs.first.parent
    expect(track["class"]).to include("animate-marquee", "hover:[animation-play-state:paused]", "motion-reduce:animate-none")
    expect(html.css("li svg").map { |node| node["aria-hidden"] }).to all(eq("true"))
    expect(html.css("li svg").map { |node| node["focusable"] }).to all(eq("false"))
  end

  it "cycles icon glyphs and renders nothing without named items" do
    names = Array.new(7) { |index| { name: "Industry #{index}" } }
    html = render_inline(described_class.new(theme: website_theme, props: { items: names }))
    paths = html.css("ul").first.css("li svg path").map { |node| node["d"] }
    expect(paths.first(6).uniq.size).to eq(6)
    expect(paths.last).to eq(paths.first)
    html = render_inline(described_class.new(theme: website_theme, props: { heading: "Orphan heading", items: [{ name: "" }] }))
    expect(html.css("section, h2")).to be_empty
  end
end
