# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member::Payments::PaymentMethods", type: :request do
  let(:customer)       { create(:customer) }
  let(:other_customer) { create(:customer) }
  let(:member_user)    { create(:user, :member, customer: customer) }
  let(:other_member)   { create(:user, :member, customer: customer) }
  let(:admin_user)     { create(:user, :admin,  customer: customer) }
  let(:index_path)     { "/#{customer.id}/member/payments/payment_methods" }

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

  before do
    Current.customer = customer
    # Ensure authentication module is enabled for both customers
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

    it "POST setup_intent redirects to sign-in" do
      post "#{index_path}/setup_intent"
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "POST create redirects to sign-in" do
      post index_path
      expect(response).to redirect_to("/auth/sign_in")
    end

    it "DELETE destroy redirects to sign-in" do
      delete "#{index_path}/999"
      expect(response).to redirect_to("/auth/sign_in")
    end
  end

  # ---------------------------------------------------------------------------
  # Admin access — member URLs must not admit admins
  # ---------------------------------------------------------------------------
  describe "admin user visiting member payment_methods URL" do
    before { sign_in admin_user }

    it "GET index is rejected by the member role gate" do
      get index_path
      expect(response).to redirect_to("/#{customer.id}/admin/assistant")
      expect(flash[:alert]).to match(/member/i)
    end

    it "DELETE destroy is rejected by the member role gate" do
      pm = create_payment_method(user: member_user)
      delete "#{index_path}/#{pm.id}"
      expect(response).to redirect_to("/#{customer.id}/admin/assistant")
      expect(flash[:alert]).to match(/member/i)
    end
  end

  # ---------------------------------------------------------------------------
  # Member can see their own cards
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

      it "shows only current member's cards, not another member's" do
        my_card    = create_payment_method(user: member_user)
        their_card = create_payment_method(user: other_member)

        get index_path
        expect(response.body).to include(my_card.last4)
        expect(response.body).not_to include(their_card.psp_payment_method_id)
      end

      it "localizes the card brand on the listing in zh-CN" do
        create_payment_method(user: member_user, brand: "unionpay", last4: "0000")

        get index_path, params: { locale: "zh-CN" }
        expect(response.body).to include("银联")
        expect(response.body).not_to include("Unionpay")
      end

      it "keys the Stripe.js widget to CredentialResolver's mode, not an arbitrary active account" do
        # Insert production first so an unordered `.active.find_by(provider:)`
        # would return it. VaultCard still charges through sandbox in test.
        create(:payment_merchant_account, :production, customer: customer, merchant_id: "acct_live",
               credentials: { publishable_key: "pk_live_prod" })
        create(:payment_merchant_account, customer: customer, merchant_id: "acct_sandbox",
               credentials: { publishable_key: "pk_test_sandbox" })

        # VaultCard mints the SetupIntent through Gateway → CredentialResolver,
        # whose default mode tracks Rails.env.production? (false here). The
        # publishable key on this page must resolve the same way so Stripe.js
        # never pairs a production pk_live with a sandbox client_secret.
        allow(Rails.env).to receive(:production?).and_return(false)

        get index_path
        expect(response.body).to include("pk_test_sandbox")
        expect(response.body).not_to include("pk_live_prod")
      end
    end

    describe "GET new" do
      it "redirects to index" do
        get "#{index_path}/new"
        expect(response).to redirect_to(index_path)
      end
    end

    describe "POST setup_intent" do
      it "returns JSON with client_secret when VaultCard succeeds" do
        allow(::Payments::Activities::VaultCard).to receive(:call).and_return({
          client_secret:  "seti_test_secret",
          payment_method: instance_double(
            ::Payments::PaymentMethod,
            id: 42
          )
        })

        post "#{index_path}/setup_intent"
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["client_secret"]).to eq("seti_test_secret")
        expect(body["payment_method_id"]).to eq(42)
      end

      it "returns 404 when the Payments module is disabled" do
        FeatureModules::CustomerAssignment.find_by!(
          customer: customer, feature_module: FeatureModules::Module.find_by!(key: "payment")
        ).update!(status: :suspended)
        allow(::Payments::Activities::VaultCard).to receive(:call)

        post "#{index_path}/setup_intent"

        expect(::Payments::Activities::VaultCard).not_to have_received(:call)
        expect(response).to have_http_status(:not_found)
      end

      it "returns a generic localized error when VaultCard raises, without leaking internal detail" do
        allow(::Payments::Activities::VaultCard).to receive(:call)
          .and_raise(::Payments::Errors::ApiError, "secret internal detail")

        post "#{index_path}/setup_intent"
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).not_to include("secret internal detail")
        body = JSON.parse(response.body)
        expect(body["error"]).to eq(I18n.t("member.flash.payment_methods.setup_failed"))
      end
    end

    describe "POST create" do
      it "redirects to index with notice when card exists" do
        pm = create_payment_method(user: member_user)
        post index_path,
             params: { payment_method_id: pm.psp_payment_method_id }
        expect(response).to redirect_to(index_path)
        expect(flash[:notice]).to match(/saved/i)
      end

      it "redirects to index with alert when card not found" do
        post index_path,
             params: { payment_method_id: "pm_nonexistent" }
        expect(response).to redirect_to(index_path)
        expect(flash[:alert]).to be_present
      end

      it "does not stamp a client-supplied id onto a pending vault row" do
        pending = create_payment_method(
          user: member_user,
          psp_payment_method_id: "pending:seti_abc"
        )

        post index_path, params: { payment_method_id: "pm_attacker" }

        expect(pending.reload.psp_payment_method_id).to eq("pending:seti_abc")
        expect(pending).not_to be_chargeable
      end
    end

    describe "DELETE destroy" do
      it "detaches and removes the card, redirects to index" do
        pm = create_payment_method(user: member_user)
        allow(::Payments::Gateway).to receive(:detach_token).and_return({ status: :removed })

        delete "#{index_path}/#{pm.id}"
        expect(response).to redirect_to(index_path)
        expect(pm.reload.status).to eq("removed")
      end

      it "cannot destroy another member's card (404)" do
        their_pm = create_payment_method(user: other_member)
        allow(::Payments::Gateway).to receive(:detach_token).and_return({ status: :removed })

        delete "#{index_path}/#{their_pm.id}"
        expect(response).to have_http_status(:not_found)
      end

      it "cannot destroy a card from another tenant (404)" do
        # Create card owned by member_user but scoped to other_customer
        other_pm = create_payment_method(user: member_user, customer: other_customer)

        delete "#{index_path}/#{other_pm.id}"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant access (member of customer A visiting customer B's URL)
  # ---------------------------------------------------------------------------
  describe "cross-tenant access" do
    before { sign_in member_user }

    it "is blocked by the tenant gate" do
      get "/#{other_customer.id}/member/payments/payment_methods"
      expect(response).to redirect_to("/#{member_user.customer_id}/member")
      expect(flash[:alert]).to match(/access denied/i)
    end
  end
end
