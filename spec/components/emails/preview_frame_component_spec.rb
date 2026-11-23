# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::PreviewFrameComponent, type: :component do
  it "renders a sandboxed iframe when srcdoc is present" do
    render_inline(described_class.new(
      srcdoc: "<!DOCTYPE html><html><body><p>Hi</p></body></html>",
      title: "Email body"
    ))

    frame = page.find("iframe[sandbox]")
    expect(frame[:title]).to eq("Email body")
    expect(frame[:sandbox]).to eq("")
    expect(frame[:srcdoc]).to include("Hi")
    expect(frame[:class]).to include("min-h-[420px]")
  end

  it "shows the empty message when srcdoc is blank" do
    render_inline(described_class.new(
      srcdoc: "",
      title: "Email body",
      empty_message: "Nothing here"
    ))

    expect(page).to have_text("Nothing here")
    expect(page).not_to have_css("iframe")
  end

  it "honours a custom min-height class" do
    render_inline(described_class.new(
      srcdoc: "<p>x</p>",
      title: "Preview",
      min_height_class: "min-h-[560px]"
    ))

    expect(page.find("iframe")[:class]).to include("min-h-[560px]")
  end
end
