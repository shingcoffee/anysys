# frozen_string_literal: true

require "rails_helper"

RSpec.describe "authentication/customer_registrations routing", type: :routing do
  it "routes GET /auth/sign_up to customer_registrations#new" do
    expect(get: "/auth/sign_up").to route_to(
      controller: "authentication/customer_registrations",
      action: "new"
    )
  end

  it "routes POST /auth/sign_up to customer_registrations#create" do
    expect(post: "/auth/sign_up").to route_to(
      controller: "authentication/customer_registrations",
      action: "create"
    )
  end

  it "routes GET /auth/sign_up/check_email to customer_registrations#check_email" do
    expect(get: "/auth/sign_up/check_email").to route_to(
      controller: "authentication/customer_registrations",
      action: "check_email"
    )
  end

  it "routes POST /auth/sign_up/resend to customer_registrations#resend" do
    expect(post: "/auth/sign_up/resend").to route_to(
      controller: "authentication/customer_registrations",
      action: "resend"
    )
  end

  it "routes GET /auth/sign_up/confirm to customer_registrations#confirm" do
    expect(get: "/auth/sign_up/confirm").to route_to(
      controller: "authentication/customer_registrations",
      action: "confirm"
    )
  end
end
