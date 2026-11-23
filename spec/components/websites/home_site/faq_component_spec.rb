# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::HomeSite::FaqComponent, type: :component do
  it "uses initially closed independent native details with full escaped answers" do
    html = render_inline(described_class.new(theme: website_theme, props: { heading: "Questions", items: [
      { question: "<b>Review?</b>", answer: "Yes.\nBefore publishing." }, { question: "Windows?", answer: "Coming soon" }
    ] }))
    expect(html.css("details").size).to eq(2)
    expect(html.css("details[open], details[name], [aria-expanded], b")).to be_empty
    expect(html.css("summary").map { |node| node["class"] }).to all(include("min-h-16", "focus-visible:ring-2", "text-[17px]"))
    expect(html.at_css("details p").text).to eq("Yes.\nBefore publishing.")
    expect(html.at_css("details p")["class"]).to include("whitespace-pre-line", "text-[16px]")
    expect(html.css("summary svg").map { |node| node["aria-hidden"] }).to eq(%w[true true])
    expect(html.css("summary svg").map { |node| node["focusable"] }).to eq(%w[false false])
    expect(html.css("details").map { |node| node["class"] }).to all(include("rounded-2xl", "border", "open:border-violet-200"))
    expect(html.css("h1, button, script, [data-controller]")).to be_empty
  end

  it "does not create anonymous question rows" do
    html = render_inline(described_class.new(theme: website_theme, props: { items: [nil, {}, { question: " ", answer: "Blank" }, { answer: "Orphaned" }] }))
    expect(html.css("details")).to be_empty
  end

  it "preserves authored question order beside a sticky intro and allows a question without inventing an answer" do
    html = render_inline(described_class.new(theme: website_theme, page_role: :pricing, props: { heading: "Pricing", items: [
      { question: "Second saved question", answer: "Stored answer" }, { question: "First saved question" }
    ] }))
    expect(html.css("summary > span").reject { |node| node["aria-hidden"] }.map(&:text)).to eq(["Second saved question", "First saved question"])
    expect(html.css("details p").map(&:text)).to eq(["Stored answer"])
    expect(html.at_css("section")["class"]).to include("bg-slate-50")
    expect(html.at_css("section > div")["class"]).to include("max-w-[1280px]", "lg:grid-cols-12")
    expect(html.at_css("details").parent["class"]).to include("w-full", "lg:col-span-8")
    expect(html.at_css("h2").ancestors.any? { |node| node["class"].to_s.include?("lg:sticky") }).to be(true)
    expect(html.css("details[name], details[open]")).to be_empty
  end
end
