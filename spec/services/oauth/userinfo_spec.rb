# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::Userinfo do
  it "returns the identity claims the desktop GUI needs" do
    customer = create(:customer)
    user = create(:user, :member, customer: customer, first_name: "Ada", last_name: "Lovelace")

    body = described_class.call(user)
    expect(body[:sub]).to eq(user.id.to_s)
    expect(body[:email]).to eq(user.email)
    expect(body[:email_verified]).to be true
    expect(body[:name]).to eq("Ada Lovelace")
    expect(body[:customer_id]).to eq(customer.id.to_s)
    expect(body[:role]).to eq("member")
  end
end
