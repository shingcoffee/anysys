# frozen_string_literal: true

require "rails_helper"

RSpec.describe FormFields::VideoElementComponent, type: :component do
  def render_video(video_url)
    render_inline(described_class.new(video_url: video_url))
  end

  it "renders youtube embed from watch URL" do
    render_video("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    expect(page).to have_css("iframe[src='https://www.youtube.com/embed/dQw4w9WgXcQ']")
  end

  it "renders youtube embed from short URL" do
    render_video("https://youtu.be/dQw4w9WgXcQ")
    expect(page).to have_css("iframe[src='https://www.youtube.com/embed/dQw4w9WgXcQ']")
  end

  it "renders vimeo embed" do
    render_video("https://vimeo.com/123456")
    expect(page).to have_css("iframe[src='https://player.vimeo.com/video/123456']")
  end

  it "renders placeholder when no URL is provided" do
    render_video("")
    expect(page).to have_text("No video URL provided")
    expect(page).not_to have_css("iframe")
  end

  it "renders placeholder for unsupported URL" do
    render_video("https://example.com/video")
    expect(page).to have_text("No video URL provided")
  end

  it "renders with 16:9 aspect ratio container" do
    render_video("https://www.youtube.com/watch?v=abc")
    expect(page).to have_css("div.aspect-video")
  end

  it "defaults alignment to center" do
    component = described_class.new(video_url: "")
    expect(component.alignment).to eq("center")
  end
end
