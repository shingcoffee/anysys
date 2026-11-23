# frozen_string_literal: true

require "rails_helper"

RSpec.describe MemberChromeHelper, type: :helper do
  let(:customer) { create(:customer) }

  it "reads the customer's public website theme" do
    create(:website, customer: customer, theme: {
      "appearance" => "dark",
      "accent" => "rose",
      "type" => "serif",
      "density" => "compact"
    })
    record = customer
    helper.define_singleton_method(:current_customer) { record }

    theme = helper.member_site_theme
    expect(theme.appearance).to eq("dark")
    expect(theme.accent).to eq("rose")
    expect(theme.type).to eq("serif")
    expect(theme.density).to eq("compact")
  end

  it "uses the public site defaults when the customer has no website" do
    record = customer
    helper.define_singleton_method(:current_customer) { record }

    expect(helper.member_site_theme.tokens).to eq(Websites::Theme::DEFAULTS)
  end
end
