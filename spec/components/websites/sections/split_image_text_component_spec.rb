# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::Sections::SplitImageTextComponent, type: :component do
  it "renders the heading from props" do
    render_inline(described_class.new(
      props: { "heading" => "Two audiences", "body" => "Members and the public.", "image_side" => "right" },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_text("Two audiences")
    expect(page).to have_text("Members and the public.")
  end

  it "shows a photo the assistant placed whole, and crops a stock photo to the frame" do
    customer = create(:customer)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("photo"), filename: "pet.png", content_type: "image/png", identify: false,
      metadata: { Websites::Activities::ImportMedia::SOURCE_KEY => 1 }
    )
    placed = "/#{customer.id}/site/media/#{blob.signed_id}"

    render_inline(described_class.new(props: { "heading" => "The shop", "image_url" => placed }, theme: website_theme))
    expect(page).to have_css("[data-photo-fit='whole'] img.object-contain[src='#{placed}']")

    render_inline(described_class.new(props: { "heading" => "The shop", "image_url" => "https://images.unsplash.com/photo-1" }, theme: website_theme))
    expect(page).to have_css("img.object-cover")
    expect(page).to have_no_css("[data-photo-fit]")
  end

  it "renders a style override on a restylable element" do
    render_inline(described_class.new(
      props: { "heading" => "Two audiences", "styles" => { "heading" => { "color" => "#be123c" } } },
      theme: website_theme,
      customer_id: 42
    ))

    expect(page).to have_css("[data-site-el='heading'][style*='#be123c']")
  end
end
