# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Member::SubscriptionsComponent, type: :component do
  let(:visa_pm) do
    Payments::PaymentMethod.new(
      brand: "visa",
      last4: "4242",
      psp_payment_method_id: "pm_visa"
    )
  end

  let(:active_sub) do
    Payments::Subscription.new(
      id:             1,
      customer_id:    99,
      provider:       "stripe",
      external_ref:   "sub_active",
      plan_name:      "Pro Monthly",
      amount: 29.99,
      currency:       "usd",
      cycle:          "monthly",
      status:         "active",
      next_charge_at: Time.zone.parse("2026-07-21 10:00:00")
    ).tap { |s| s.payment_method = visa_pm }
  end

  let(:cancelled_sub) do
    Payments::Subscription.new(
      id:           2,
      customer_id:  99,
      provider:     "alipay",
      external_ref: "sub_cancelled",
      plan_name:    "Basic Yearly",
      amount: 99.00,
      currency:     "cny",
      cycle:        "yearly",
      status:       "cancelled",
      next_charge_at: nil
    )
  end

  def cancel_url_for(sub)
    "/99/member/payments/subscriptions/#{sub.id}/cancellation"
  end

  def render_component(subscriptions:, recovery_for: ->(_s) { nil }, publishable_key: nil)
    render_inline(described_class.new(subscriptions: subscriptions, cancel_url_for: method(:cancel_url_for),
                                      recovery_for: recovery_for, publishable_key: publishable_key))
  end

  let(:paused_sub) do
    Payments::Subscription.new(
      id: 3, customer_id: 99, provider: "stripe", external_ref: "sub_paused",
      plan_name: "Pro Monthly", amount: 29.99, currency: "usd", cycle: "monthly",
      status: "paused", next_charge_at: nil
    ).tap { |s| s.payment_method = visa_pm }
  end

  describe "on-session SCA recovery" do
    it "renders the verification widget for a paused sub with a recovery context" do
      render_component(subscriptions: [paused_sub], publishable_key: "pk_live_x",
                       recovery_for: ->(s) { s == paused_sub ? { client_secret: "cs_paused" } : nil })

      expect(page).to have_text("Complete verification")
      expect(page).to have_css('[data-controller="payments--sca-recovery"]')
      expect(page).to have_css('[data-payments--sca-recovery-client-secret-value="cs_paused"]')
      expect(page).to have_css('[data-payments--sca-recovery-publishable-key-value="pk_live_x"]')
    end

    it "does not render the widget when there is no recovery context" do
      render_component(subscriptions: [paused_sub], recovery_for: ->(_s) { nil })
      expect(page).not_to have_text("Complete verification")
      expect(page).not_to have_css('[data-controller="payments--sca-recovery"]')
      expect(page).to have_button("Cancel")
    end

    it "shows the cancel action (not recovery) for an active sub" do
      render_component(subscriptions: [active_sub])
      expect(page).to have_button("Cancel")
      expect(page).not_to have_text("Complete verification")
    end
  end

  describe "#initialize" do
    it "accepts an array of subscriptions and a cancel_url_for callable" do
      component = described_class.new(
        subscriptions:  [active_sub],
        cancel_url_for: method(:cancel_url_for)
      )
      expect(component.subscriptions).to eq([active_sub])
    end

    it "accepts an empty subscriptions array" do
      component = described_class.new(
        subscriptions:  [],
        cancel_url_for: method(:cancel_url_for)
      )
      expect(component.subscriptions).to be_empty
    end
  end

  describe "rendering — empty state" do
    it "renders the empty state when no subscriptions" do
      render_component(subscriptions: [])
      expect(page).to have_text("No subscriptions")
    end
  end

  describe "rendering — subscription list" do
    before do
      render_component(subscriptions: [active_sub, cancelled_sub])
    end

    it "renders the plan name for each subscription" do
      expect(page).to have_text("Pro Monthly")
      expect(page).to have_text("Basic Yearly")
    end

    it "renders the formatted amount + currency for each subscription" do
      # 2999 USD cents → 29.99 or $29.99
      expect(page).to have_text("29.99")
      expect(page).to have_text("USD")
      expect(page).to have_text("99.00")
      expect(page).to have_text("CNY")
    end

    it "renders zero-decimal subscription amounts without fractional digits" do
      jpy_sub = active_sub.dup
      jpy_sub.assign_attributes(amount: 2999.00, currency: "jpy")

      render_component(subscriptions: [jpy_sub])

      expect(page).to have_text("2999 JPY")
      expect(page).not_to have_text("2999.00 JPY")
    end

    it "renders the billing cycle for each subscription" do
      expect(page).to have_text("Monthly")
      expect(page).to have_text("Yearly")
    end

    it "localizes the billing cycle in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        render_component(subscriptions: [active_sub])
        expect(page).to have_text(I18n.t("comp_payments.member.subscriptions.cycles.monthly"))
      end
    end

    it "renders the status badge for each subscription" do
      expect(page).to have_text("Active")
      expect(page).to have_text("Cancelled")
    end

    it "renders the linked card display_label when a payment_method is present" do
      expect(page).to have_text("Visa •••• 4242")
    end

    it "renders next charge date for active subscription" do
      expect(page).to have_text(I18n.l(Date.new(2026, 7, 21), format: :long))
    end

    it "localizes next charge date in zh-CN" do
      I18n.with_locale(:"zh-CN") do
        render_component(subscriptions: [active_sub])
        expect(page).to have_text(I18n.l(Date.new(2026, 7, 21), format: :long))
      end
    end

    it "renders a Cancel button for live subscriptions, not cancelled ones" do
      expect(page).to have_button("Cancel")
      # cancelled_sub must NOT have a Cancel button
      expect(page).to have_button("Cancel", count: 1)
    end

    it "Cancel form posts to the cancel_url_for the subscription" do
      expect(page).to have_css(
        "form[action='/99/member/payments/subscriptions/1/cancellation'][method='post']"
      )
    end

    it "does not render Cancel for the cancelled subscription" do
      expect(page).not_to have_css(
        "form[action='/99/member/payments/subscriptions/2/cancellation']"
      )
    end
  end

  describe "accessibility" do
    it "renders subscriptions in a list or table structure" do
      render_component(subscriptions: [active_sub])
      expect(page).to have_css("table, ul, ol, [role='list']")
    end
  end

  describe "#cycle_label" do
    it "falls back to the raw key for an unknown cycle" do
      unknown = Payments::Subscription.new(cycle: "fortnightly")
      component = described_class.new(subscriptions: [], cancel_url_for: method(:cancel_url_for))
      expect(component.cycle_label(unknown)).to eq("fortnightly")
    end
  end

  describe "#status_label" do
    it "falls back to the raw key for an unknown status" do
      unknown = Payments::Subscription.new(status: "unknown")
      component = described_class.new(subscriptions: [], cancel_url_for: method(:cancel_url_for))
      expect(component.status_label(unknown)).to eq("unknown")
    end
  end
end
