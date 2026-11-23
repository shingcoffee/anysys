# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CustomerSubscriptionComponent, type: :component do
  let(:plan) { build(:billing_plan, code: "monthly", name: "Monthly", amount_usd: 30, amount_cny: 210) }
  let(:yearly) { build(:billing_plan, :yearly, code: "annual", name: "Annual", amount_usd: 300, amount_cny: 2100) }
  let(:subscription) do
    build(:billing_subscription, customer: nil, customer_id: 12345678, plan: plan,
      amount_cents: 2400, currency: "USD", current_period_end: Time.zone.local(2026, 10, 23),
      plan_snapshot: { "code" => "monthly", "name" => "Purchased monthly" })
  end
  let(:key) { "987b603e-cb63-4b40-a8b5-5fc5db7e5aa8" }

  def render_plan(**options)
    render_inline described_class.new(plans: [plan, yearly], current_subscription: subscription,
      enabled_items: [], currency: "CNY", customer_id: 12345678, **options)
  end

  it "uses purchased terms and stored currency independently of language and catalog" do
    I18n.with_locale(:"zh-CN") do
      render_plan
      within("#current-subscription") do
        expect(page).to have_text("Purchased monthly")
        expect(page).to have_text("$24.00 USD")
        expect(page).not_to have_text("¥210.00")
      end
      expect(page).to have_text("$300.00 USD")
      expect(page).not_to have_css(".translation_missing")
    end
  end

  it "reviews cadence changes through GET and submits only the accepted plan and stable key" do
    render_plan(plan_review: { plan: yearly, kind: :scheduled, allowed: true,
      effective_at: subscription.current_period_end }, request_key: key)
    expect(page).to have_link("Review plan change", href: /plan_change_preview.*plan_code=annual/)
    within("form[action='/12345678/admin/settings/billing/subscription']") do
      expect(page).to have_css('input[name="billing_subscription[request_key]"]', visible: :all)
      expect(page).to have_css("input[value='#{key}']", visible: :all)
      expect(page).to have_css('input[name="billing_subscription[plan_code]"][value="annual"]', visible: :all)
      expect(page).not_to have_css('input[name*="currency"], input[name*="amount"], input[name*="effective_at"]', visible: :all)
    end
  end

  it "shows an immediate estimate without granting the target before settlement" do
    render_plan(plan_review: { plan: yearly, kind: :immediate, allowed: true,
      currency: "USD", total_cents: 1200 })
    expect(page).to have_text("Charge now: $12.00 USD")
    expect(page).to have_text("including in manual collection mode")
    within("#current-subscription") { expect(page).not_to have_text("Annual") }
  end

  it "displays the durable scheduled target and disables conflicting changes" do
    change = double(status: "scheduled", target_snapshot: { name: "Accepted annual", amount_cents: 30000,
      currency: "USD", interval: "yearly" }, effective_at: subscription.current_period_end)
    render_plan(pending_plan_change: change)
    expect(page).to have_text("Accepted annual")
    expect(page).to have_text("Scheduled")
    expect(page).to have_button("Cancel pending change")
    expect(page).not_to have_link("Review plan change")
    expect(page).to have_button("Review plan change", disabled: true)
    expect(page).to have_css("[data-plan-changes-blocked]", text: I18n.t("settings_billing.subscription.change_blocked"), count: 1)
  end

  it "omits the blocked notice when every other plan can be reviewed" do
    subscription.status = "active"
    render_plan
    expect(page).not_to have_css("[data-plan-changes-blocked]")
  end

  it "shows finite fallback usage without advertising unimplemented meters" do
    items = %w[page entity member storage].map { |key| double(key: key, label: key.capitalize) }
    render_inline described_class.new(plans: [], current_subscription: nil, enabled_items: items,
      currency: "USD", customer_id: 12345678, entitlements: { source: :free, limits: { page: 10, entity: 5, member: 1 } },
      usage: { page: 12, entity: 2, member: 1 })
    expect(page).to have_text("12 / 10")
    expect(page).to have_text("Finite free-plan limits")
    expect(page).not_to have_text("Storage")
  end

  it "retains accepted coupon benefit and redemption-relative remaining cycles" do
    render_plan(coupon_benefit: { code: "SAVE20", name: "Accepted offer", discount_type: "percent",
      percent_off: 20, duration: "repeating", remaining_cycles: 2, eligible: true })
    expect(page).to have_text("2 eligible billed cycles remaining")
    within("#subscription-coupon") { expect(page).to have_text("Coupon") }
    expect(page).not_to have_field("coupon_redemption[coupon_code]")
  end

  it "keeps ended history read-only and makes its former plan selectable again" do
    subscription.assign_attributes(status: "cancelled", cancel_at_period_end: true, ended_at: Time.zone.local(2026, 9, 20))
    render_inline described_class.new(plans: [plan], current_subscription: nil, latest_subscription: subscription,
      enabled_items: [], currency: "USD", customer_id: 12345678)
    expect(page).to have_text("Most recent ended subscription")
    expect(page).to have_text("September 20, 2026")
    expect(page).to have_css("button[data-action='modal-dialog#open']", text: "Review subscription")
    expect(page).to have_css("dialog#subscribe-plan-monthly", visible: :all)
    expect(page).not_to have_css("summary, details")
    expect(page).not_to have_text("Scheduled cancellation")
  end

  it "does not advertise a catalog price for an unsupported stored currency" do
    subscription.currency = "EUR"
    render_plan
    expect(page).to have_text("stored currency EUR")
    expect(page).not_to have_link("Review plan change")
    expect(page).not_to have_text("$300.00")
  end

  it "retains the request key and invalid signup coupon on 422 without syncing the model" do
    form = Billing::Contracts::Subscribe.new(OpenStruct.new(request_key: key, coupon_code: "INVALID", plan_code: yearly.code, currency: "USD"))
    form.errors.add(:coupon_code, "is invalid")
    render_inline described_class.new(plans: [yearly], current_subscription: nil, enabled_items: [], currency: "USD",
      customer_id: 12345678, form: form, plan_review: { plan: yearly, allowed: true, kind: :initial })
    expect(page).to have_field("billing_subscription[coupon_code]", with: "INVALID")
    expect(page).to have_css("input[value='#{key}']", visible: :all)
    expect(page).to have_css('input[aria-invalid="true"][aria-describedby="billing_subscription_coupon_code_error"]')
  end

  it "opens the enrollment dialog on a 422 when no review panel is present" do
    form = Billing::Contracts::Subscribe.new(OpenStruct.new(request_key: key, coupon_code: "INVALID", plan_code: yearly.code, currency: "USD"))
    form.errors.add(:coupon_code, "is invalid")
    render_inline described_class.new(plans: [yearly], current_subscription: nil, enabled_items: [], currency: "USD",
      customer_id: 12345678, form: form)
    expect(page).to have_css('[data-controller="modal-dialog"][data-modal-dialog-open-value="true"]')
    expect(page).to have_field("billing_subscription[coupon_code]", with: "INVALID", visible: :all)
  end

  it "uses server resume eligibility rather than a stored cancellation flag" do
    subscription.status = "paused"
    render_plan(subscription_actions: { can_cancel: true, can_resume: false })
    expect(page).not_to have_button("Keep subscription")
    expect(page).to have_button("Cancel Subscription")
    subscription.assign_attributes(status: "trialing", cancel_at_period_end: true)
    render_plan(subscription_actions: { can_cancel: false, can_resume: true })
    expect(page).to have_button("Keep subscription")
    expect(page).not_to have_button("Cancel Subscription")
  end

  it "renders cancellation for a server-eligible pending subscription through the wrapper" do
    subscription.status = "pending"
    render_inline Billing::Admin::PlanComparisonComponent.new(plans: [], current_subscription: subscription,
      enabled_items: [], currency: "USD", customer_id: 12345678,
      subscription_actions: { can_cancel: true, can_resume: false }, can_cancel: true, can_resume: false)
    expect(page).to have_button("Cancel Subscription")
    expect(page).not_to have_button("Keep subscription")
  end

  it "honors explicit false action flags even when a stale action map says true" do
    subscription.cancel_at_period_end = true
    render_plan(subscription_actions: { can_cancel: true, can_resume: true }, can_cancel: false, can_resume: false)
    expect(page).not_to have_css("#manage-subscription")
  end

  it "shows the controller's recovery reason, invoices and saved grace deadline" do
    debt = double(id: 19, number: "INV-12345678-00019", to_param: "19")
    render_plan(subscription_actions: { can_cancel: false, can_resume: false }, recovery: {
      can_cancel: false, can_resume: false, invoices: [debt], grace_deadline: Time.zone.local(2026, 10, 28),
      reason_key: "settings_billing.subscription.states.past_due"
    })
    within("[aria-labelledby='billing-recovery-heading']") do
      expect(page).to have_text(I18n.t("settings_billing.subscription.states.past_due"))
      expect(page).to have_text("October 28, 2026")
      expect(page).to have_link("Invoice INV-12345678-00019", href: "/12345678/admin/settings/billing/invoices/19")
    end
    expect(page).not_to have_button("Keep subscription")
  end

  it "puts a blocked preview reason first without advertising its placeholder zero charge" do
    reason = I18n.t("admin_settings.flash.billing.reasons.pending_change_exists")
    render_plan(plan_review: { plan: yearly, allowed: false, kind: :immediate, currency: "USD", total_cents: 0,
      effective_at: subscription.current_period_end, reason_key: "admin_settings.flash.billing.reasons.pending_change_exists" })
    within("[aria-labelledby='plan-review-heading']") do
      expect(page).to have_css('[role="alert"]', text: reason)
      expect(page).not_to have_text("Charge now")
      expect(page).not_to have_text("$0.00 USD")
      expect(page).not_to have_text("Effective on")
      expect(page).not_to have_css("form")
    end
    review = page.find("[aria-labelledby='plan-review-heading']").native.to_html
    expect(review.index(reason)).to be < review.index("Change to Annual")
  end

  it "summarizes the default payment method with a single manage link" do
    method = double(provider: "alipay", display_label: "buyer@example.com")
    render_plan(default_payment_method: method)
    within("#current-subscription") do
      expect(page).to have_text("Alipay (China)")
      expect(page).to have_text("buyer@example.com")
      expect(page).to have_link("Manage", href: "/12345678/admin/settings/billing/payment_methods", count: 1)
      expect(page).not_to have_link(href: "/12345678/admin/settings/billing/invoices")
    end
  end

  it "offers a jump to plan comparison from the current subscription" do
    render_plan
    within("#current-subscription") { expect(page).to have_link("Change plan", href: "#compare-plans") }
  end

  it "invites a customer without a subscription to browse plans" do
    render_inline described_class.new(plans: [plan], current_subscription: nil, enabled_items: [], currency: "USD", customer_id: 12345678)
    within("#current-subscription") do
      expect(page).to have_css("h2", text: "No active subscription")
      expect(page).to have_link("Browse plans", href: "#compare-plans")
      expect(page).not_to have_link("Change plan")
    end
    expect(page).to have_css("#compare-plans")
    expect(page).not_to have_css('#compare-plans[data-controller="billing-disclosure"]')
    expect(page).to have_css("li[data-plan-code='monthly']")
  end

  it "states when no default payment method is set" do
    render_plan
    within("#current-subscription") { expect(page).to have_text("No default payment method is set.") }
  end

  it "renders bounded usage meters and flags an exceeded quota" do
    items = %w[page entity member].map { |key| double(key: key, label: key.capitalize) }
    render_inline described_class.new(plans: [], current_subscription: nil, enabled_items: items,
      currency: "USD", customer_id: 12345678,
      entitlements: { source: :free, limits: { page: 10, entity: 4, member: Billing::PlanLimit::UNLIMITED } },
      usage: { page: 12, entity: 1, member: 3 })
    within("[aria-labelledby='billing-usage-heading']") do
      expect(page).to have_css("dd.text-danger", text: "12 / 10")
      expect(page).to have_css(".bg-danger[style='width: 100%']")
      expect(page).to have_css(".bg-accent[style='width: 25%']")
      expect(page).to have_text("3 / Unlimited")
      expect(page).to have_css("[style^='width']", count: 2)
    end
  end

  it "highlights the current plan card and anchors plan reviews to the review panel" do
    subscription.status = "active"
    render_plan
    expect(page).to have_css("li[data-plan-code='monthly'].ring-accent", text: "Current")
    expect(page).to have_button("Current Plan", disabled: true)
    expect(page).to have_link("Review plan change", href: /plan_code=annual.*#plan-review\z/)
  end

  it "retains coupon-redemption input and domain field errors on the separate live form" do
    render_plan(coupon_code: "BAD-CODE", errors: { coupon_code: ["Coupon code not found."] })
    expect(page).to have_field("coupon_redemption[coupon_code]", with: "BAD-CODE")
    expect(page).to have_css('input[name="coupon_redemption[coupon_code]"][aria-invalid="true"]')
    within("#subscription-coupon") { expect(page).to have_text("Coupon code not found.") }
  end

  it "filters paid plans by interval when monthly and yearly catalogs both exist" do
    render_plan
    expect(page).to have_css('[data-controller="billing-plan-catalog"]')
    within('[role="radiogroup"][aria-label="Billing interval"]') do
      expect(page).to have_css('[role="radio"][aria-checked="true"][data-billing-plan-catalog-interval-param="monthly"]', text: "Monthly")
      expect(page).to have_css('[role="radio"][aria-checked="false"][data-billing-plan-catalog-interval-param="yearly"]', text: "Yearly")
      expect(page).to have_css('[data-action="billing-plan-catalog#selectInterval keydown->billing-plan-catalog#keydown"]', count: 2)
    end
  end

  it "omits the interval filter when every paid plan shares one interval" do
    render_inline described_class.new(plans: [plan], current_subscription: nil, enabled_items: [],
      currency: "USD", customer_id: 12345678)
    expect(page).not_to have_css('[data-controller="billing-plan-catalog"]')
    expect(page).not_to have_css('[role="radiogroup"]')
  end

  it "itemizes subtotal and tax on an immediate plan-change review" do
    render_plan(plan_review: { plan: yearly, kind: :immediate, allowed: true, currency: "USD",
      subtotal_cents: 1000, tax_cents: 200, total_cents: 1200 })
    within("#plan-review") do
      expect(page).to have_text("Change to Annual")
      expect(page).not_to have_text("Selected plan")
      expect(page).not_to have_text(I18n.t("settings_billing.subscription.trial_policy_hint"))
      expect(page).to have_text("Subtotal")
      expect(page).to have_text("$10.00 USD")
      expect(page).to have_text("Tax")
      expect(page).to have_text("$2.00 USD")
      expect(page).to have_text("Charge now: $12.00 USD")
    end
  end

  it "tags the subscription price with the active coupon code" do
    render_plan(coupon_benefit: { code: "SAVE20", name: "Accepted offer", discount_type: "percent",
      percent_off: 20, duration: "repeating", remaining_cycles: 2, eligible: true })
    within("#current-subscription") do
      expect(page).to have_css("[title='Active coupon']", text: "SAVE20")
      expect(page).not_to have_link(href: "#subscription-coupon")
    end
  end

  it "opens a one-time payment dialog from recovery without duplicating the footer CTA" do
    debt = double(id: 19, number: "INV-12345678-00019", to_param: "19")
    render_plan(
      recovery: { invoices: [debt], reason_key: "settings_billing.subscription.states.past_due" },
      one_time_payment: {
        kind: "unpaid_invoice", invoice_id: 19, invoice_number: "INV-12345678-00019",
        currency: "USD", amount_cents: 2400, providers: [{ key: "stripe" }]
      }
    )
    expect(page).to have_css('[data-controller="modal-dialog"][data-modal-dialog-open-value="false"]')
    expect(page).to have_css("button[data-action='modal-dialog#open'][aria-controls='one-time-payment-dialog']", text: "Make one-time payment", count: 1)
    within("[aria-labelledby='billing-recovery-heading']") do
      expect(page).to have_css("button.btn-primary", text: "Make one-time payment")
      expect(page).to have_link("Invoice INV-12345678-00019", class: "btn-secondary")
    end
    within("#current-subscription") do
      expect(page).not_to have_css("button", text: "Make one-time payment")
    end
    dialog = page.find("dialog#one-time-payment-dialog", visible: :all)
    expect(dialog).to have_css("*", text: "Outstanding invoice", visible: :all)
    expect(dialog).to have_css('form[action="/12345678/admin/settings/billing/subscription/one_time_payment"]', visible: :all)
  end

  it "offers one-time payment in the current subscription actions when recovery is absent" do
    render_plan(one_time_payment: {
      kind: "renewal", currency: "USD", amount_cents: 2400, providers: [{ key: "stripe" }]
    })
    expect(page).not_to have_css("[aria-labelledby='billing-recovery-heading']")
    expect(page).to have_css("button[data-action='modal-dialog#open'][aria-controls='one-time-payment-dialog']", text: "Make one-time payment", count: 1)
    within("#current-subscription [data-subscription-actions]") do
      expect(page).to have_css("button.btn-primary", text: "Make one-time payment")
    end
  end

  it "opens the one-time payment dialog after a rejected attempt" do
    render_plan(one_time_payment: { kind: "renewal", currency: "USD", amount_cents: 2400, providers: [{ key: "stripe" }] },
      one_time_open: true, one_time_error: "That provider could not start a payment.")
    expect(page).to have_css('[data-controller="modal-dialog"][data-modal-dialog-open-value="true"]')
    expect(page).to have_css('[role="alert"]', text: "That provider could not start a payment.", visible: :all)
    expect(page).to have_css("*", text: "Current-period renewal", visible: :all)
  end

  it "does not wrap the subscription page in a one-time dialog without a payable invoice" do
    render_plan
    expect(page).not_to have_css("dialog#one-time-payment-dialog", visible: :all)
    expect(page).not_to have_button("Make one-time payment")
  end

  it "keeps plans visible and groups coupon and cancellation under subscription settings" do
    render_plan(subscription_actions: { can_cancel: true, can_resume: false })
    expect(page).not_to have_css('[data-controller="billing-disclosure"]')
    expect(page).to have_css("#compare-plans li[data-plan-code='annual']")
    within("[aria-labelledby='subscription-settings-heading']") do
      expect(page).to have_css("#subscription-coupon", text: "Coupon")
      expect(page).to have_field("coupon_redemption[coupon_code]")
      expect(page).to have_css("#manage-subscription", text: "Cancel subscription")
      expect(page).to have_button("Cancel Subscription")
    end
  end

  it "offers to keep a cancelling plan instead of cancelling it again" do
    subscription.cancel_at_period_end = true
    render_plan(subscription_actions: { can_cancel: false, can_resume: true })
    within("#manage-subscription") do
      expect(page).to have_text("Cancels at end of current period")
      expect(page).to have_text("October 23, 2026")
      expect(page).to have_button("Keep subscription")
      expect(page).not_to have_button("Cancel Subscription")
    end
  end

  it "shows price, a date-only renewal and no redundant period range" do
    subscription.assign_attributes(status: "active", current_period_start: Time.zone.local(2026, 9, 23, 15, 6))
    render_plan
    within("#current-subscription dl") do
      expect(page).to have_css("dt", text: "Subscription price")
      expect(page).to have_css("dt", text: "Renewal date")
      expect(page).to have_text("October 23, 2026")
      expect(page).not_to have_text("September 23, 2026")
      expect(page).not_to have_text("UTC")
    end
  end

  it "explains platform entitlements once without a redundant badge" do
    items = %w[page entity member].map { |key| double(key: key, label: key.capitalize) }
    render_inline described_class.new(plans: [], current_subscription: nil, enabled_items: items,
      currency: "USD", customer_id: 12345678,
      entitlements: { source: :platform, limits: { page: Billing::PlanLimit::UNLIMITED, entity: Billing::PlanLimit::UNLIMITED, member: Billing::PlanLimit::UNLIMITED } },
      usage: { page: 12, entity: 2, member: 1 })
    within("[aria-labelledby='billing-usage-heading']") do
      expect(page).not_to have_text("Unrestricted")
      expect(page).to have_text("The platform account has unrestricted quota access.")
    end
  end
end
