# frozen_string_literal: true

require "rails_helper"

RSpec.describe Websites::FittedPhotoComponent, type: :component do
  it "shows the photo whole over a blurred copy, inside the section's frame without the crop" do
    render_inline(described_class.new(
      src: "/81721200/site/media/pets", alt: "Four pets",
      css_class: "absolute inset-0 size-full object-cover grayscale-[35%]", eager: true
    ))

    frame = page.find("[data-photo-fit='whole']")
    expect(frame[:class].split).to include("absolute", "inset-0", "size-full", "grayscale-[35%]", "flex", "overflow-hidden")
    expect(frame[:class].split).not_to include("object-cover")
    expect(frame).to have_css("img.blur-3xl[aria-hidden='true'][alt=''][src='/81721200/site/media/pets'][loading='eager']")
    expect(frame).to have_css("img.object-contain.max-w-full.max-h-full[alt='Four pets'][src='/81721200/site/media/pets']")
    expect(frame).to have_no_css("img[style]")
  end

  it "loads lazily unless the section asks for eager" do
    render_inline(described_class.new(src: "/81721200/site/media/pets"))

    expect(page).to have_css("img[loading='lazy']", count: 2, visible: :all)
  end
end
