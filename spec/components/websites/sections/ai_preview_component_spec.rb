# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::AiPreviewComponent, type: :component do
  let(:props) do
    {
      "kicker" => "A first draft", "heading" => "From request to workspace", "subhead" => "Keep control of the result.",
      "example_label" => "Illustrative example", "prompt_label" => "Your request",
      "prompt" => "Create a volunteer workspace and public website.", "review_note" => "Review before publishing.",
      "output_label" => "Workspace preview", "items" => [
        { "title" => "Volunteer records", "body" => "Names and availability", "status" => "Draft" },
        { "title" => "Registration form", "body" => "Collect the details you need", "status" => "Draft" },
        { "title" => "Public website", "body" => "Home, opportunities, contact", "status" => "Draft" }
      ]
    }
  end

  it "renders the request, review note, and three output cards in reading order without interactive controls" do
    render_inline(described_class.new(props: props, theme: website_theme, customer_id: 42))

    expect(page).to have_css("h2", text: props["heading"])
    expect(page).to have_css("article", count: 3)
    expect(page.all("article h3").map(&:text)).to eq(props["items"].pluck("title"))
    expect(page).to have_css("article span", text: "Draft", count: 3)
    expect(page.text.index(props["prompt"])).to be < page.text.index(props["review_note"])
    expect(page.text.index(props["review_note"])).to be < page.text.index(props["output_label"])
    props.except("items").each_value { |text| expect(page).to have_text(text) }
    expect(page).not_to have_css("h1, button, input, a, script, [data-controller], [role='status']")
    expect(page).to have_css("[aria-hidden='true'] svg", count: 4)
    expect(page).to have_css("svg", count: 4)
  end

  it "omits blank optional labels and hides an empty output group" do
    blank_props = props.merge("example_label" => " ", "prompt_label" => "", "review_note" => nil, "items" => [])
    render_inline(described_class.new(props: blank_props, theme: website_theme))

    expect(page).to have_text(props["prompt"])
    expect(page).not_to have_text(props["example_label"])
    expect(page).not_to have_text(props["prompt_label"])
    expect(page).not_to have_text(props["review_note"])
    expect(page).not_to have_text(props["output_label"])
    expect(page).not_to have_css("article, p:empty")
  end

  it "renders an empty section without fallback copy" do
    render_inline(described_class.new(theme: website_theme))

    expect(page.text.strip).to be_empty
    expect(page).not_to have_css("article, h2, h3, p")
  end

  it "supports four outputs, optional status, and Chinese copy in the dark theme" do
    localized = props.merge(
      "heading" => "从需求到工作空间", "prompt" => "创建志愿者管理工作空间，并配备公开网站。",
      "items" => Array.new(4) { { "title" => "可审核的草稿", "body" => "发布前可继续编辑和完善。", "status" => "" } }
    )
    render_inline(described_class.new(props: localized, theme: website_theme("appearance" => "dark")))

    expect(page).to have_css("h2", text: localized["heading"])
    expect(page).to have_css("article.bg-neutral-950", count: 4)
    expect(page).to have_css("article h3", text: "可审核的草稿", count: 4)
    expect(page).not_to have_css("article span.rounded-full")
  end

  it "escapes owner-authored text in labels and output cards" do
    unsafe = props.merge("prompt" => "<script>alert(1)</script>", "items" => [{ "title" => "<b>Title</b>", "status" => "<img src=x>" }])
    render_inline(described_class.new(props: unsafe, theme: website_theme))

    expect(page).to have_text("<script>alert(1)</script>")
    expect(page).to have_text("<b>Title</b>")
    expect(page).not_to have_css("script, img, b")
  end

  it "renders a style override on the prompt" do
    render_inline(described_class.new(
      props: props.merge("styles" => { "prompt" => { "color" => "#be123c" } }),
      theme: website_theme
    ))

    expect(page).to have_css("[data-site-el='prompt'][style*='#be123c']")
  end
end
