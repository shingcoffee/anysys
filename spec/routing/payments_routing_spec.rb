require "rails_helper"

RSpec.describe "Payment routes", type: :routing do
  it "routes GET checkout" do
    expect(get: "/12345678/payments/checkout").to route_to(
      controller: "payments/checkouts", action: "show", customer_id: "12345678"
    )
  end

  it "routes POST checkout" do
    expect(post: "/12345678/payments/checkout").to route_to(
      controller: "payments/checkouts", action: "create", customer_id: "12345678"
    )
  end

  it "routes wechat_pay webhook (no tenant scope)" do
    expect(post: "/payments/webhooks/wechat_pay").to route_to(
      controller: "payments/webhooks", action: "create", provider: "wechat_pay"
    )
  end

  it "routes alipay webhook (no tenant scope)" do
    expect(post: "/payments/webhooks/alipay").to route_to(
      controller: "payments/webhooks", action: "create", provider: "alipay"
    )
  end

  # The route constraint is now a lambda that delegates to Payments::Gateways.keys
  # at request time, so every registered gateway (including Stripe) is routable
  # without any change to routes.rb.
  it "routes stripe webhook (no tenant scope)" do
    expect(post: "/payments/webhooks/stripe").to route_to(
      controller: "payments/webhooks", action: "create", provider: "stripe"
    )
  end

  it "rejects webhook for a completely unknown/unsupported provider" do
    expect(post: "/payments/webhooks/not_a_real_gateway").not_to be_routable
  end

  it "routes admin refund under modules/payments" do
    expect(post: "/12345678/admin/modules/payments/transactions/5/refunds").to route_to(
      controller: "admin/modules/payments/refunds", action: "create",
      customer_id: "12345678", transaction_id: "5"
    )
  end
end
