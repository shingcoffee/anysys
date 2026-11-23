# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::PlatformSettings do
  it "defaults public customer sign-up to enabled" do
    described_class.delete_all
    expect(described_class.customer_signup_enabled?).to be(true)
  end

  it "persists the kill switch" do
    described_class.instance.update!(allow_customer_signup: false)
    expect(described_class.customer_signup_enabled?).to be(false)
  end
end
