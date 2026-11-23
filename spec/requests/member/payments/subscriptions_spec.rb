# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member::Payments::Subscriptions", type: :request do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:member_user)    { create(:user, :member, customer: customer) }
  let(:other_member)   { create(:user, :member, customer: customer) }
  let(:admin_user)     { create(:user, :admin,  customer: customer) }
  let(:index_path)     { "/#{customer.id}/member/payments/subscriptions" }

  def create_payment_method(user:, customer: nil, **attrs)
    create(:payment_method, {
      user:       user,
      customer:   customer || user.customer,
      provider:   "stripe",
      brand:      "visa",
      last4:      "4242",
      exp_month:  12,
      exp_year:   2099,
      status:     "active"
    }.merge(attrs))
  end

  def create_subscription(payment_method:, **attrs)
    create(:payment_subscription, {
      customer:       payment_method.customer,
      provider:      "stripe",
      plan_name:     "gold",
      amount: 9.99,
      currency:      "usd",
      cycle:         "monthly",
      status:        "active",
      payment_method: payment_method
    }.merge(attrs))
  end

  before do
    Current.customer = customer
    [ customer, other_customer ].each { |c| enable_module!("authentication", c, name: "Authentication") }
    enable_module!("payment", customer, name: "Payments")
  end

  # ---------------------------------------------------------------------------
  # Anonymous access
  # ---------------------------------------------------------------------------
  describe "anonymous user" do
    it "GET index redirects to sign-in" do
      get index_path
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "GET show redirects to sign-in" do
      get "#{index_path}/1"
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "POST cancellation redirects to sign-in" do
      post "#{index_path}/1/cancellation"
      expect(response).to redirect_to("/auth/sign_in")
    end
  end

  # ---------------------------------------------------------------------------
  # Admin access — member URLs must not admit admins
  # ---------------------------------------------------------------------------
  describe "admin user visiting member subscription URL" do
    before { sign_in admin_user }

    it "GET index is rejected by the member role gate" do
      get index_path
      expect(response).to redirect_to("/#{customer.id}/admin/assistant")
      expect(flash[:alert]).to match(/member/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Member can see their own subscriptions
  # ---------------------------------------------------------------------------
  describe "authenticated member" do
    before do
      sign_in member_user
      Current.customer = customer
    end

    describe "GET index" do
      it "renders 200" do
        get index_path
        expect(response).to have_http_status(:ok)
      end

      it "shows only subscriptions linked to current member's cards" do
        my_pm    = create_payment_method(user: member_user)
        their_pm = create_payment_method(user: other_member)

        my_sub    = create_subscription(payment_method: my_pm, plan_name: "mine")
        their_sub = create_subscription(payment_method: their_pm, plan_name: "theirs")

        get index_path
        expect(response.body).to include("mine")
        expect(response.body).not_to include("theirs")
      end

      it "caps the subscription listing at 100 rows" do
        payment_method = create_payment_method(user: member_user)
        101.times do |i|
          create_subscription(payment_method: payment_method, plan_name: "plan-#{i}")
        end

        get index_path

        expect(response).to have_http_status(:ok)
        expect(Nokogiri::HTML(response.body).css("tbody tr").count).to eq(100)
      end

      it "surfaces the SCA-recovery widget for a paused sub with a pending 3DS charge" do
        create(:payment_merchant_account, customer: customer, merchant_id: "acct_m",
               credentials: { publishable_key: "pk_test_member" })

        my_pm  = create_payment_method(user: member_user)
        my_sub = create_subscription(payment_method: my_pm, plan_name: "sca-plan", status: "paused")
        order  = create(:payment_order, customer: customer, currency: "USD", subject: "sca-plan",
                         amount: 9.99, external_ref: "sub-#{my_sub.id}-#{Date.today}")
        create(:payment, customer: customer, payment_order: order, provider: "stripe", flow: "card",
               out_trade_no: "ct-sca-req", amount: 9.99, status: "pending",
               prepay_payload: { "requires_action" => true, "client_secret" => "cs_member_secret" })

        get index_path
        expect(response.body).to include("Complete verification")
        expect(response.body).to include("cs_member_secret")
        expect(response.body).to include("pk_test_member")
      end

      it "does not bind SCA recovery to another subscription whose id shares a decimal prefix" do
        create(:payment_merchant_account, customer: customer, merchant_id: "acct_m",
               credentials: { publishable_key: "pk_test_member" })

        my_pm  = create_payment_method(user: member_user)
        my_sub = create_subscription(payment_method: my_pm, plan_name: "mine", status: "paused")
        their_pm  = create_payment_method(user: other_member)
        create_subscription(payment_method: their_pm, plan_name: "theirs", status: "paused")

        colliding = "sub-#{my_sub.id}0-#{Date.today}"
        their_order = create(:payment_order, customer: customer, currency: "USD", subject: "theirs",
                              amount: 9.99, external_ref: colliding)
        create(:payment, customer: customer, payment_order: their_order, provider: "stripe", flow: "card",
               out_trade_no: "ct-sca-other", amount: 9.99, status: "pending",
               prepay_payload: { "requires_action" => true, "client_secret" => "cs_other_member_secret" })

        get index_path
        expect(response.body).not_to include("cs_other_member_secret")
      end

      it "keys the SCA widget to the recovery payment's own mode, not an arbitrary active account" do
        create(:payment_merchant_account, customer: customer, merchant_id: "acct_sandbox",
               credentials: { publishable_key: "pk_test_sandbox" })

        create(:payment_merchant_account, :production, customer: customer, merchant_id: "acct_live",
               credentials: { publishable_key: "pk_live_prod" })

        my_pm  = create_payment_method(user: member_user)
        my_sub = create_subscription(payment_method: my_pm, plan_name: "sca-sandbox-plan", status: "paused")
        order  = create(:payment_order, customer: customer, currency: "USD", subject: "sca-sandbox-plan",
                         amount: 9.99, external_ref: "sub-#{my_sub.id}-#{Date.today}")
        create(:payment, customer: customer, payment_order: order, provider: "stripe", flow: "card",
               out_trade_no: "ct-sca-sandbox", amount: 9.99, status: "pending",
               prepay_payload: { "requires_action" => true, "client_secret" => "cs_sandbox_secret" })

        # The recovery payment's client_secret was minted while the app resolved
        # credentials in "sandbox" mode (CredentialResolver's default mode tracks
        # Rails.env.production?, which is false here). The publishable key must be
        # resolved the same way so it always pairs with the account that owns the
        # client_secret — never an arbitrary active row (e.g. the other mode).
        allow(Rails.env).to receive(:production?).and_return(false)

        get index_path
        expect(response.body).to include("cs_sandbox_secret")
        expect(response.body).to include("pk_test_sandbox")
        expect(response.body).not_to include("pk_live_prod")
      end
    end

    describe "GET show" do
      it "renders own subscription" do
        my_pm  = create_payment_method(user: member_user)
        my_sub = create_subscription(payment_method: my_pm, plan_name: "myplan")

        get "#{index_path}/#{my_sub.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("myplan")
      end

      it "returns 404 when subscription belongs to another member" do
        their_pm  = create_payment_method(user: other_member)
        their_sub = create_subscription(payment_method: their_pm, plan_name: "theirs")

        get "#{index_path}/#{their_sub.id}"
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 when subscription is in another tenant" do
        # PaymentMethod + Subscription both scoped to other_customer
        other_pm  = create_payment_method(user: member_user, customer: other_customer)
        other_sub = create_subscription(payment_method: other_pm, plan_name: "xplan",
                                        external_ref: "xsub_#{SecureRandom.hex(5)}",
                                        amount: 5.00)

        get "#{index_path}/#{other_sub.id}"
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST cancellation (cancel)" do
      it "cancels own subscription and redirects to index" do
        my_pm  = create_payment_method(user: member_user)
        my_sub = create_subscription(payment_method: my_pm)

        allow(::Payments::Activities::CancelSubscription).to receive(:call).and_return(my_sub)

        post "#{index_path}/#{my_sub.id}/cancellation"
        expect(response).to redirect_to(index_path)
        expect(flash[:notice]).to match(/cancel/i)
        expect(::Payments::Activities::CancelSubscription).to have_received(:call).with(
          customer: customer, subscription: my_sub, detach_orphaned_token: false
        )
      end

      it "returns 404 when the Payments module is disabled" do
        FeatureModules::CustomerAssignment.find_by!(
          customer: customer, feature_module: FeatureModules::Module.find_by!(key: "payment")
        ).update!(status: :suspended)
        my_pm  = create_payment_method(user: member_user)
        my_sub = create_subscription(payment_method: my_pm)
        allow(::Payments::Activities::CancelSubscription).to receive(:call)

        post "#{index_path}/#{my_sub.id}/cancellation"

        expect(::Payments::Activities::CancelSubscription).not_to have_received(:call)
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 when trying to cancel another member's subscription" do
        their_pm  = create_payment_method(user: other_member)
        their_sub = create_subscription(payment_method: their_pm)

        post "#{index_path}/#{their_sub.id}/cancellation"
        expect(response).to have_http_status(:not_found)
      end

      it "redirects with an alert when the payment provider is not configured" do
        my_pm  = create_payment_method(user: member_user)
        my_sub = create_subscription(payment_method: my_pm)
        allow(::Payments::Activities::CancelSubscription).to receive(:call)
          .and_raise(Payments::Errors::CredentialsMissing, "none")

        post "#{index_path}/#{my_sub.id}/cancellation"

        expect(response).to redirect_to(index_path)
        expect(flash[:alert]).to eq(I18n.t("comp_payments.flash.subscription_cancel_unavailable"))
      end

      it "returns 404 when trying to cancel a subscription in another tenant" do
        other_pm  = create_payment_method(user: member_user, customer: other_customer)
        other_sub = create_subscription(payment_method: other_pm, plan_name: "xplan2",
                                        external_ref: "xsub2_#{SecureRandom.hex(5)}",
                                        amount: 5.00)

        post "#{index_path}/#{other_sub.id}/cancellation"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant access
  # ---------------------------------------------------------------------------
  describe "cross-tenant access" do
    before { sign_in member_user }

    it "is blocked by the tenant gate on index" do
      get "/#{other_customer.id}/member/payments/subscriptions"
      expect(response).to redirect_to("/#{member_user.customer_id}/member")
      expect(flash[:alert]).to match(/access denied/i)
    end
  end
end
