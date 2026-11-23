# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Locale do
  it "prefers the user's available locale over the customer's" do
    user = instance_double(Authentication::User, locale: "zh-CN")
    customer = instance_double(Customer, locale: "en")

    expect(described_class.for(user: user, customer: customer)).to eq(:"zh-CN")
  end

  it "falls through to the customer's available locale" do
    user = instance_double(Authentication::User, locale: nil)
    customer = instance_double(Customer, locale: "zh-CN")

    expect(described_class.for(user: user, customer: customer)).to eq(:"zh-CN")
  end

  it "skips a locale that is not available and uses the next one" do
    user = instance_double(Authentication::User, locale: "fr")
    customer = instance_double(Customer, locale: "zh-CN")

    expect(described_class.for(user: user, customer: customer)).to eq(:"zh-CN")
  end

  it "returns the default locale when none of the chain is available" do
    user = instance_double(Authentication::User, locale: "fr")
    customer = instance_double(Customer, locale: "de")

    expect(described_class.for(user: user, customer: customer)).to eq(I18n.default_locale)
  end

  it "returns the default locale when user and customer are missing" do
    expect(described_class.for(user: nil, customer: nil)).to eq(I18n.default_locale)
  end

  it "matches available locales by string, including a symbol stored value" do
    user = instance_double(Authentication::User, locale: :"zh-CN")
    customer = instance_double(Customer, locale: nil)

    expect(described_class.for(user: user, customer: customer)).to eq(:"zh-CN")
  end
end
