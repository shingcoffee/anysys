# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::DraftComponent, type: :component do
  it "shows the entire saved brief and output outlines as escaped static text on a dark board" do
    html = render_inline(described_class.new(theme: website_theme, props: {
      heading: "Connected drafts", example_label: "Example", prompt_label: "Brief", prompt: "Build <em>membership</em>",
      output_label: "Outputs", review_note: "Review before publishing",
      items: [{ title: "Records", status: "Draft", body: "Name · Email\nRenewal date" }, { title: "Form", body: "Editable" }]
    }))
    expect(html).to have_css("h2", text: "Connected drafts")
    expect(html).to have_css("article", count: 2)
    expect(html.css("article").first.css("li").map { |node| node.text.strip }).to eq(["Name · Email", "Renewal date"])
    expect(html.at_css("h3")["class"]).to include("text-[18px]", "text-white")
    expect(html.css("article span").find { |node| node.text.strip == "Draft" }["class"]).to include("text-[12px]")
    expect(html.css("p").find { |node| node.text.include?("Build <em>membership</em>") }["class"]).to include("text-[19px]")
    expect(html).to have_text("Review before publishing")
    expect(html.css("em, img, input, button, a")).to be_empty
    expect(html.css("svg").map { |node| node["aria-hidden"] }).to all(eq("true"))
    expect(html.css("svg").map { |node| node["focusable"] }).to all(eq("false"))
    board = html.at_css("article").ancestors.find { |node| node["class"].to_s.include?("rounded-[2rem]") }
    expect(board["class"]).to include("bg-slate-950")
    expect(html.css("[class]").any? { |node| node["class"].include?("md:grid-cols-3") }).to be(true)
  end

  it "does not fabricate outputs or labels for empty props" do
    html = render_inline(described_class.new(theme: website_theme))
    expect(html.css("h2, h3, p, article")).to be_empty
    expect(html.css("svg, [aria-hidden], .shadow-2xl")).to be_empty
  end

  it "omits blank edited outputs and lets outputs fill the board when the brief is removed" do
    html = render_inline(described_class.new(theme: website_theme, props: { items: [
      nil, {}, { title: "  ", body: "" }, { title: "Website", body: "First saved output" },
      { status: "Under review" }, { title: "Records", body: "Last saved output" }
    ] }))
    expect(html.css("article").size).to eq(3)
    expect(html.css("article h3").map(&:text)).to eq(%w[Website Records])
    expect(html).to have_text("Under review")
    expect(html.at_css("article").ancestors.any? { |node| node["class"].to_s.include?("lg:col-span-12") }).to be(true)
    expect(html.css("article svg path").map { |node| node["d"] }.uniq.size).to eq(3)
    expect(html.css("h1, input, button, a")).to be_empty
  end
end
