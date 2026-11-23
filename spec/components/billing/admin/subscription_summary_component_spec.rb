# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::SubscriptionSummaryComponent, type: :component do
  let(:plan) do
    instance_double(Billing::Plan, name: "Pro Monthly", code: "pro-monthly")
  end

  let(:coupon) { instance_double(Billing::Coupon, code: "SAVE10") }

  def build_subscription(status:, cancel_at_period_end: false, coupon: nil, customer: nil)
    instance_double(
      Billing::Subscription,
      id:                   1,
      plan:                 plan,
      status:               status,
      amount_cents:         9900,
      currency:             "CNY",
      interval:             "monthly",
      current_period_start: Time.zone.local(2026, 6, 1),
      current_period_end:   Time.zone.local(2026, 7, 1),
      trial_end:            nil,
      ended_at:             Time.zone.local(2026, 6, 20),
      cancel_at_period_end?: cancel_at_period_end,
      coupon:               coupon,
      customer:             customer,
      customer_id:          "12345678"
    )
  end

  def render_summary(subscription:, **opts)
    render_inline(described_class.new(subscription: subscription, customer_id: "12345678", **opts))
  end

  before do
    stub_helpers = double(
      "helpers",
      admin_settings_billing_subscription_path: "/12345678/admin/settings/billing/subscription",
      admin_settings_billing_cancellation_path: "/12345678/admin/settings/billing/cancellation",
      admin_maintenance_platform_billing_subscription_cancellation_path: "/81721200/admin/maintenance/platform/billing/subscriptions/1/cancellation",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  describe "no subscription" do
    it "shows the no-subscription empty state" do
      render_summary(subscription: nil)
      expect(page).to have_text("No active subscription.")
    end

    it "shows subscribe button only when show_actions is true" do
      render_summary(subscription: nil, show_actions: true)
      expect(page).to have_link("Choose a Plan")
    end

    it "does not show subscribe button when show_actions is false" do
      render_summary(subscription: nil, show_actions: false)
      expect(page).not_to have_link("Choose a Plan")
    end
  end

  describe "status badge rendering" do
    {
      "trialing"  => "Trialing",
      "active"    => "Active",
      "past_due"  => "Past due",
      "cancelled" => "Cancelled"
    }.each do |status, badge_text|
      it "shows #{badge_text} badge for #{status} status" do
        render_summary(subscription: build_subscription(status: status))
        expect(page).to have_text(badge_text)
      end
    end
  end

  describe "active subscription details" do
    subject(:sub) { build_subscription(status: "active") }

    before { render_summary(subscription: sub) }

    it "renders plan name, formatted amount, and next renewal date" do
      aggregate_failures do
        expect(page).to have_text("Pro Monthly")
        expect(page).to have_text("¥99.00")
        expect(page).to have_text(I18n.l(Date.new(2026, 7, 1), format: :long))
      end
    end

    it "localizes the billing period in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        render_summary(subscription: sub)
        expect(page).to have_text(I18n.l(Date.new(2026, 6, 1), format: :long))
        expect(page).to have_text(I18n.l(Date.new(2026, 7, 1), format: :long))
      end
    end
  end

  describe "cancel_at_period_end" do
    let(:sub) { build_subscription(status: "active", cancel_at_period_end: true) }

    it "shows cancellation notice" do
      render_summary(subscription: sub)
      expect(page).to have_text("set to cancel at the end of the current billing period")
    end

    it "shows resume button when show_actions is true" do
      render_summary(subscription: sub, show_actions: true, subscription_actions: { can_resume: true, can_cancel: false })
      expect(page).to have_button("Resume Subscription")
    end
  end

  describe "action buttons" do
    let(:sub) { build_subscription(status: "active") }

    it "shows change plan and cancel when show_actions is true" do
      render_summary(subscription: sub, show_actions: true, subscription_actions: { can_resume: false, can_cancel: true })
      aggregate_failures do
        expect(page).to have_link("Change Plan")
        expect(page).to have_button("Cancel Subscription")
      end
    end

    it "hides action buttons when show_actions is false" do
      render_summary(subscription: sub, show_actions: false)
      aggregate_failures do
        expect(page).not_to have_link("Change Plan")
        expect(page).not_to have_button("Cancel Subscription")
      end
    end
  end

  describe "coupon display" do
    it "shows coupon code when present" do
      sub = build_subscription(status: "active", coupon: coupon)
      render_summary(subscription: sub, coupon_benefit: { code: "SAVE10", name: "Accepted discount", discount_type: "percent",
        percent_off: 10, duration: "once", remaining_cycles: 1, eligible: true })
      expect(page).to have_text("SAVE10")
    end
  end

  it "gives terminal status precedence over a leftover cancellation schedule" do
    render_summary(subscription: build_subscription(status: "cancelled", cancel_at_period_end: true))
    expect(page).to have_text("Ended on")
    expect(page).not_to have_text("Scheduled cancellation")
    expect(page).not_to have_text("set to cancel at the end")
  end

  it "uses explicit action flags instead of inferring permission from active status" do
    render_summary(subscription: build_subscription(status: "active", cancel_at_period_end: true), show_actions: true,
      subscription_actions: { can_cancel: true, can_resume: true }, can_cancel: false, can_resume: false)
    expect(page).not_to have_button("Cancel Subscription")
    expect(page).not_to have_button("Resume Subscription")
  end

  describe "platform operator danger zone" do
    let(:sub) { build_subscription(status: "active") }

    it "renders immediate cancel as a danger-zone row with confirmation" do
      render_summary(subscription: sub, platform: true, can_cancel_immediately: true)
      expect(page).to have_text("Danger zone")
      expect(page).to have_button("Cancel immediately")
      expect(page).to have_css("[data-turbo-confirm]")
      expect(page).not_to have_css("details, summary")
    end

    it "keeps the pending plan change as a status callout" do
      render_summary(subscription: sub, platform: true, pending_plan_change: {
        status: "scheduled", effective_at: Time.zone.local(2026, 7, 1),
        target_snapshot: { name: "Pro Yearly", amount_cents: 99000, currency: "CNY", interval: "yearly" }
      })
      expect(page).to have_css("[role='status']", text: "Pro Yearly")
      expect(page).to have_text("Yearly")
    end
  end

  describe "status_variant" do
    {
      "trialing"  => :info,
      "active"    => :success,
      "past_due"  => :danger,
      "paused"    => :warning,
      "cancelled" => :default,
      "expired"   => :default
    }.each do |status, expected|
      it "returns #{expected} for #{status}" do
        sub = build_subscription(status: status)
        expect(described_class.new(subscription: sub, customer_id: "12345678").status_variant).to eq(expected)
      end
    end
  end
end
