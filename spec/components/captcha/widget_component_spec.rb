# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::WidgetComponent, type: :component do
  let!(:settings) { create(:captcha_provider_settings) }

  it "renders the vendor widget when a provider is active" do
    output = render_inline(described_class.new)
    expect(output.css("[data-controller='captcha-aliyun']")).to be_present
    expect(output.css("input[type='hidden'][name='captcha_verify_param']")).to be_present
  end

  it "renders nothing when credentials are missing" do
    settings.update!(access_key_id: nil, access_key_secret: nil)
    settings.write_config(scene_id: nil)
    settings.save!
    expect(render_inline(described_class.new).to_html.strip).to be_blank
  end

  it "is only rendered from the challenge interstitial" do
    hits = Dir[Rails.root.join("app/{views,components}/**/*.{erb,rb}")].filter_map do |path|
      next if path.end_with?("challenge_component.html.erb")
      next if path.end_with?("widget_component.rb")
      next if path.end_with?("widget_component.html.erb")

      path.delete_prefix("#{Rails.root}/") if File.read(path).include?("Captcha::WidgetComponent")
    end
    expect(hits).to eq([])
  end
end
