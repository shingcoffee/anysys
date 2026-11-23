# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::StoryIndexComponent, type: :component do
  let(:stories) do
    [
      { "kicker" => "Reported essay", "title" => "The harbor at night", "body" => "Who keeps a city open.", "byline" => "By Samir Aziz", "href" => "essay",
        "image_url" => "https://images.unsplash.com/photo-1?w=1400" },
      { "kicker" => "Education", "title" => "A school that kept its shop class", "href" => "essay" },
      { "title" => "What we will not cover" },
      { "kicker" => "City", "title" => "The last bookbinder", "byline" => "6 min read" },
      { "title" => "" }
    ]
  end

  it "splits stories into a lead, two secondary stories and briefs" do
    component = described_class.new(props: { "heading" => "The front page", "stories" => stories }, theme: website_theme, customer_id: 42)

    expect(component.lead["title"]).to eq("The harbor at night")
    expect(component.secondary.map { |story| story["title"] }).to eq(["A school that kept its shop class", "What we will not cover"])
    expect(component.briefs.map { |story| story["title"] }).to eq(["The last bookbinder"])
  end

  it "renders a ruled masthead and links stories that have an href" do
    render_inline(described_class.new(props: { "kicker" => "This week", "heading" => "The front page", "stories" => stories }, theme: website_theme, customer_id: 12345678))

    expect(page).to have_css("h2", text: "The front page")
    expect(page).to have_text("This week")
    expect(page).to have_link(href: "/12345678/essay", count: 2)
    expect(page).to have_css("article", text: "What we will not cover")
    expect(page).to have_text("By Samir Aziz")
    expect(page).to have_css("img[src^='https://images.unsplash.com/photo-1']")
    expect(rendered_content).to include("border-neutral-950")
  end

  it "renders nothing but the section shell without stories" do
    render_inline(described_class.new(props: { "stories" => [] }, theme: website_theme("appearance" => "dark"), customer_id: 42))

    expect(page).not_to have_css("h3")
  end

  it "drops unsafe links and images and escapes authored markup" do
    unsafe = [
      { "title" => "<script>alert(1)</script>", "href" => "javascript:alert(1)", "image_url" => "javascript:alert(1)" },
      { "title" => "Second", "href" => "http://evil.example" }
    ]
    render_inline(described_class.new(props: { "stories" => unsafe }, theme: website_theme, customer_id: 42))

    expect(page).to have_text("<script>alert(1)</script>")
    expect(page).not_to have_css("script")
    expect(page).not_to have_css("a")
    expect(page).not_to have_css("img[src^='javascript']")
  end

  it "renders a style override on a restylable element" do
    render_inline(described_class.new(
      props: { "heading" => "The front page", "stories" => stories, "styles" => { "heading" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='heading'][style*='#be123c']")
  end
end
