# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::PlanComparisonComponent, type: :component do
  it "forwards review, fallback, history and request identity through the wrapper" do
    plan = build(:billing_plan, code: "pro", amount_usd: 30)
    render_inline described_class.new(plans: [plan], current_subscription: nil, enabled_items: [], currency: "USD",
      customer_id: 12345678, customer_settings: true, entitlements: { source: :free, limits: {} },
      request_key: "4b5ce1fb-6bf3-445c-88ae-f1f534bca397", plan_review: { plan: plan, allowed: true })
    expect(page).to have_text("Finite free-plan limits")
    expect(page).to have_button("Subscribe")
    expect(page).to have_css('input[name="billing_subscription[request_key]"][value="4b5ce1fb-6bf3-445c-88ae-f1f534bca397"]', visible: :all)
    expect(page).to have_css('ul[aria-label="Compare plans"] > li[data-plan-code="pro"]')
  end
end
