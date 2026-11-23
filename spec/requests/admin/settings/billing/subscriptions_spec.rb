# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/billing/subscriptions", type: :request do
  include_context "admin records"
  let!(:plan) { create(:billing_plan) }
  let(:request_key) { SecureRandom.uuid }
  let(:path) { admin_settings_billing_subscription_path(customer.id) }
  let(:guard_path) { path }
  let(:payload) { { billing_subscription: { plan_code: plan.code, request_key: request_key } } }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :patch

  describe "GET billing settings root" do
    let(:guard_path) { admin_settings_billing_path(customer.id) }

    it_behaves_like "an admin-guarded GET"
  end

  describe "plan preview guards" do
    let(:guard_path) { plan_change_preview_admin_settings_billing_subscription_path(customer.id) }
    it_behaves_like "an admin-guarded GET"
  end

  describe "authorized commands" do
    before { sign_in admin }

    it "passes only the purchasing customer, catalog records and stable identity to Subscribe" do
      expect(Billing::Activities::Subscribe).to receive(:call).with(
        customer: customer, plan: plan, coupon: nil, request_key: request_key
      ).and_return(Billing::Result.new(status: :awaiting_payment))
      patch path, params: { billing_subscription: payload[:billing_subscription].merge(
        customer_id: create(:customer).id, amount_cents: 1, currency: "USD", merchant_account_id: 4,
        plan_snapshot: { amount_cents: 1 }, return_url: "https://attacker.example/"
      ) }
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.subscriptions.subscription_pending"))
    end

    it "retains the original request key on repeated submits" do
      expect(Billing::Activities::Subscribe).to receive(:call).with(
        customer: customer, plan: plan, coupon: nil, request_key: request_key
      ).twice.and_return(Billing::Result.new(status: :unchanged))
      2.times { patch path, params: payload }
      expect(response).to have_http_status(:see_other)
    end

    it "refuses missing/invalid identities rather than minting a new request on POST" do
      expect(Billing::Activities::Subscribe).not_to receive(:call)
      patch path, params: { billing_subscription: { plan_code: plan.code, request_key: "untrusted" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["status"]).to eq("invalid")
    end

    it "does not silently discard an unknown coupon at enrollment" do
      expect(Billing::Activities::Subscribe).not_to receive(:call)
      patch path, params: { billing_subscription: payload[:billing_subscription].merge(coupon_code: "UNKNOWN") }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "reports real asynchronous enrollment as awaiting payment while its accepted invoice is still draft" do
      patch path, params: payload
      expect(response).to have_http_status(:see_other)
      accepted = Billing::Subscription.where(customer_id: customer.id, request_key: request_key).sole
      expect(accepted.status).to eq("pending")
      expect(accepted.invoices.sole.status).to eq("draft")
      expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.subscriptions.subscription_pending"))
      expect(flash[:notice]).not_to eq(I18n.t("admin_settings.flash.subscriptions.subscribed", name: plan.name))
    end

    context "with a live subscription" do
      let!(:subscription) { create(:billing_subscription, customer: customer, currency: "CNY") }

      it "does not announce an unpaid asynchronous upgrade as applied" do
        target = create(:billing_plan, amount_cny: "199.00", interval: "monthly", trial_days: 0)
        original_plan_id = subscription.billing_plan_id
        patch path, params: { billing_subscription: { plan_code: target.code, request_key: request_key } }
        expect(response).to have_http_status(:see_other)
        change = Billing::PlanChange.where(customer_id: customer.id, request_key: request_key).sole
        expect(change.status).to eq("awaiting_payment")
        expect(change.proration_invoice.status).to eq("draft")
        expect(subscription.reload.billing_plan_id).to eq(original_plan_id)
        expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.subscriptions.plan_change_pending"))
      end

      it "reports scheduled timing instead of claiming immediate plan application" do
        effective_at = subscription.current_period_end
        change = instance_double(Billing::PlanChange, effective_at: effective_at)
        expect(Billing::Activities::ChangePlan).to receive(:call).with(
          subscription: subscription, new_plan: plan, request_key: request_key
        ).and_return(Billing::Result.new(status: :scheduled, plan_change: change))
        patch path, params: payload
        expect(response).to have_http_status(:see_other)
        expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.subscriptions.plan_change_scheduled",
                                          date: I18n.l(effective_at, format: :long)))
      end

      it "returns 409 for a conflicting target without a success notice" do
        allow(Billing::Activities::ChangePlan).to receive(:call).and_return(
          Billing::Result.new(status: :conflict, reason: :pending_change_exists)
        )
        patch path, params: payload, as: :json
        expect(response).to have_http_status(:conflict)
        expect(response.parsed_body["reason"]).to eq("pending_change_exists")
        expect(flash[:notice]).to be_nil
      end

      it "uses A's read-only preview, ignoring browser pricing and currency" do
        at = subscription.current_period_end
        expect(Billing::PlanChangePolicy).to receive(:preview).with(subscription: subscription, new_plan: plan)
          .and_return(kind: :scheduled, effective_at: at, currency: "CNY", subtotal_cents: 9900,
                      tax_cents: 0, total_cents: 9900, allowed: true, reason: nil, private_data: "hidden")
        expect(Billing::Activities::ChangePlan).not_to receive(:call)
        get plan_change_preview_admin_settings_billing_subscription_path(customer.id),
            params: { plan_code: plan.code, amount_cents: 1, currency: "USD" }, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include("currency" => "CNY", "total_cents" => 9900, "effective_at" => at.iso8601)
        expect(response.parsed_body).not_to have_key("private_data")
      end

      it "keeps stored currency in the overview across locale changes" do
        expect(Billing::AvailableProviders).to receive(:call).with(customer: customer, currency: "CNY").and_return([])
        get path, params: { locale: "en" }
        expect(response).to have_http_status(:ok)
      end
    end

    context "with logically ended subscriptions awaiting cron" do
      before do
        allow(Billing::Onboarding).to receive(:call)
        Billing::Settings.current.update!(grace_period_days: 7)
        create(:billing_plan, :default_plan)
      end

      def capture_overview
        allow_any_instance_of(Admin::Settings::Billing::SubscriptionsController).to receive(:render).and_wrap_original do |original, *args, **kwargs|
          @overview = %i[subscription latest_subscription form pending_plan_change entitlements].to_h do |key|
            [key, original.receiver.instance_variable_get("@#{key}")]
          end
          original.call(*args, **kwargs)
        end
      end

      it "offers reenrollment on GET without changing a cancellation-boundary row or claiming a current schedule" do
        old = create(:billing_subscription, customer: customer, plan: plan,
          current_period_start: 1.month.ago, current_period_end: 1.day.ago, cancel_at_period_end: true)
        capture_overview
        stored = old.attributes
        get path
        expect(response).to have_http_status(:ok)
        expect(@overview[:subscription]).to be_nil
        expect(@overview[:latest_subscription]).to eq(old)
        expect(@overview[:pending_plan_change]).to be_nil
        expect(@overview[:form]).to be_a(Billing::Contracts::Subscribe)
        expect(@overview[:entitlements].source).to eq(:free)
        expect(response.body).to include(I18n.t("settings_billing.subscription.review_subscription"))
        expect(old.reload.attributes).to eq(stored)
      end

      it "routes an overdue pending initial request through real Subscribe and keeps its original unpaid invoice" do
        accepted = travel_to(10.days.ago) do
          Billing::Activities::Subscribe.call(customer: customer, plan: plan, request_key: SecureRandom.uuid)
        end
        Billing::Activities::FinalizeInvoice.call(invoice: accepted.invoice)
        original_key = accepted.subscription.request_key
        expect(Billing::Activities::ChangePlan).not_to receive(:call)
        patch path, params: payload
        expect(response).to have_http_status(:see_other)
        expect(accepted.subscription.reload.status).to eq("expired")
        expect(accepted.subscription.request_key).to eq(original_key)
        expect(accepted.invoice.reload.status).to eq("open")
        current = Billing::Subscription.where(customer_id: customer.id).live.first
        expect(current.id).not_to eq(accepted.subscription.id)
        expect(current.request_key).to eq(request_key)
        expect(current.status).to eq("pending")
      end

      it "reenrolls after actual trial grace without granting a repeat trial" do
        trial_plan = create(:billing_plan, :with_trial)
        accepted = travel_to(22.days.ago) do
          Billing::Activities::Subscribe.call(customer: customer, plan: trial_plan, request_key: SecureRandom.uuid)
        end
        patch path, params: { billing_subscription: { plan_code: trial_plan.code, request_key: request_key } }
        expect(response).to have_http_status(:see_other)
        expect(accepted.subscription.reload.status).to eq("expired")
        current = Billing::Subscription.where(customer_id: customer.id).live.first
        expect(current.status).to eq("pending")
        expect(current.trial_end).to be_nil
        expect(customer.reload.trial_used_at).to be_present
      end

      it "keeps pending and overdue renewable-within-grace rows current despite free/grace entitlement sources" do
        old = create(:billing_subscription, customer: customer, plan: plan,
          current_period_start: 1.month.ago, current_period_end: 1.day.ago)
        capture_overview
        get path
        expect(@overview[:subscription]).to eq(old)
        expect(@overview[:entitlements].source).to eq(:grace)
        expect(@overview[:form]).to be_a(Billing::Contracts::ChangePlan)
        old.update!(status: "pending", current_period_start: Time.current, current_period_end: 1.month.from_now)
        get path
        expect(@overview[:subscription]).to eq(old)
        expect(@overview[:entitlements].source).to eq(:free)
        expect(@overview[:form]).to be_a(Billing::Contracts::ChangePlan)
      end

      it "does not preview a scheduled change against a logically ended row" do
        create(:billing_subscription, customer: customer, current_period_end: 20.days.ago)
        expect(Billing::PlanChangePolicy).not_to receive(:preview)
        get plan_change_preview_admin_settings_billing_subscription_path(customer.id), params: { plan_code: plan.code }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include("allowed" => false, "reason" => "no_active_subscription")
      end

      it "admits initial enrollment with finite Starter fallback when the default is absent" do
        Billing::Plan.default_plan.destroy!
        patch path, params: payload, as: :json
        expect(response).to have_http_status(:see_other)
        expect(Billing::Subscription.where(customer_id: customer.id).live.count).to eq(1)
        expect(Billing::Entitlements.for(customer: customer).limits).to eq("page" => 50, "entity" => 25, "member" => 5)
      end
    end

    it "denies cross-tenant commands before calling Subscribe" do
      other = create(:customer)
      expect(Billing::Activities::Subscribe).not_to receive(:call)
      patch admin_settings_billing_subscription_path(other.id), params: payload, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns the workspace at the billing settings root" do
      get admin_settings_billing_path(customer.id)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("[data-billing-tabs] a[aria-current='page']")["href"])
        .to eq(admin_settings_billing_subscription_path(customer.id))
    end

    it "isolates tab badges to the signed-in customer's open invoices and pending methods" do
      other = create(:customer)
      foreign_subscription = create(:billing_subscription, customer: other)
      2.times { create(:billing_invoice, :open, customer: other, subscription: foreign_subscription) }
      2.times { create(:billing_payment_method, customer: other) }
      create(:billing_invoice, :open, customer: customer, subscription: create(:billing_subscription, customer: customer))
      create(:billing_payment_method, customer: customer)

      get admin_settings_billing_path(customer.id)
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('[data-tab-count="invoices"]').text).to eq("1")
      expect(document.at_css('[data-tab-count="payment_methods"]').text).to eq("1")
    end

    it "blocks a tenant admin from another customer's billing settings root" do
      other = create(:customer)
      get admin_settings_billing_path(other.id)
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(response.location.to_s).not_to include("sign_in")
    end

    it "opens compare-plans without billing-disclosure when the tenant is unsubscribed" do
      get admin_settings_billing_path(customer.id)
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      compare = document.at_css("#compare-plans")
      expect(compare).to be_present
      expect(compare["data-controller"].to_s).not_to include("billing-disclosure")
      expect(document.at_css("#compare-plans [data-plan-code]")).to be_present
      expect(document.at_css("#subscription-coupon")).to be_nil
      expect(document.at_css("#manage-subscription")).to be_nil
    end

    context "with a healthy live subscription" do
      let!(:subscription) { create(:billing_subscription, customer: customer) }

      it "shows plans, coupon, and cancellation directly without disclosures" do
        get admin_settings_billing_path(customer.id)
        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        expect(document.at_css('[data-controller="billing-disclosure"]')).to be_nil
        expect(document.at_css("#compare-plans [data-plan-code]")).to be_present
        settings = document.at_css("[aria-labelledby='subscription-settings-heading']")
        expect(settings.at_css('#subscription-coupon input[name="coupon_redemption[coupon_code]"]')).to be_present
        expect(settings.at_css("#manage-subscription").text).to include(I18n.t("comp_billing.plan_comparison.cancel_subscription"))
      end
    end

    context "with a past-due subscription and unpaid invoice" do
      let!(:subscription) { create(:billing_subscription, :past_due, customer: customer) }
      let!(:debt) do
        create(:billing_invoice, :open, customer: customer, subscription: subscription,
               total_cents: 9900, subtotal_cents: 9900)
      end

      it "puts a single Make one-time payment CTA on the recovery callout, not the subscription actions" do
        get admin_settings_billing_path(customer.id)
        expect(response).to have_http_status(:ok)
        document = Nokogiri::HTML(response.body)
        cta = I18n.t("settings_billing.one_time_payment.cta")
        openers = document.css('button[data-action="modal-dialog#open"][aria-controls="one-time-payment-dialog"]')
        expect(openers.size).to eq(1)
        expect(openers.first.text).to include(cta)

        recovery = document.at_css("[aria-labelledby='billing-recovery-heading']")
        expect(recovery.at_css("button.btn-primary").text).to include(cta)
        overview = document.at_css("#current-subscription")
        expect(overview.css("button").any? { |button| button.text.include?(cta) }).to be(false)
      end
    end
  end

  describe "platform owner billing settings root" do
    it "returns 200 for the platform owner on /81721200/admin/settings/billing" do
      owner = find_or_create_platform_owner
      sign_in owner
      get admin_settings_billing_path(owner.customer.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-billing-tabs")
    end

    it "lets the platform owner read another tenant's billing settings workspace" do
      owner = find_or_create_platform_owner
      sign_in owner
      get admin_settings_billing_path(customer.id)
      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML(response.body).at_css("[data-billing-tabs]")).to be_present
    end
  end
end
