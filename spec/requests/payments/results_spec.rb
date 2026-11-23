# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Payments::Results", type: :request do
  let_it_be(:customer) { create(:customer) }

  # Build a minimal payment + order directly via AR (no factory exists yet).
  let(:order) do
    create(:payment_order,
      customer:     customer,
      external_ref: "test-order-#{SecureRandom.hex(4)}",
      amount: 10.00,
      currency:     "CNY",
      subject:      "Test order",
      status:       "pending"
    )
  end

  let(:payment) do
    create(:payment,
      customer:      customer,
      payment_order: order,
      provider:      "alipay",
      flow:          "qr",
      out_trade_no:  "trade-#{SecureRandom.hex(6)}",
      amount: 10.00,
      status:        "created"
    )
  end

  def result_path(payment_id = payment.out_trade_no)
    payment_result_path(customer_id: customer.id, payment_id: payment_id)
  end

  before do
    allow(Payments::Activities::Query).to receive(:call)
  end

  # ---------------------------------------------------------------------------
  # GET /:customer_id/payments/result/:payment_id — happy path
  # ---------------------------------------------------------------------------
  describe "GET show" do
    it "returns 200 for a payment in 'created' status" do
      get result_path
      expect(response).to have_http_status(:ok)
      expect(Payments::Activities::Query).to have_received(:call)
    end

    it "renders a full storefront HTML page for a Turbo-driven visit" do
      get result_path, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("<html")
    end

    it "renders for an Alipay in-app browser that Rails :modern would 406" do
      get result_path, headers: {
        "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 AliApp(AP/10.5.36.6000) AlipayClient/10.5.36.6000"
      }
      expect(response).to have_http_status(:ok)
    end

    it "returns 200 for a succeeded payment" do
      payment.update!(status: "succeeded", psp_transaction_id: "PSP-001", paid_at: Time.current)
      get result_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payment successful")
      expect(Payments::Activities::Query).not_to have_received(:call)
    end

    it "returns 200 for a failed payment" do
      payment.update_column(:status, "failed")
      get result_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payment not completed")
      expect(response.body).to include("Status: Failed")
    end

    it "returns 200 for a pending payment" do
      payment.update_column(:status, "pending")
      get result_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Status: Pending")
    end

    it "returns 200 for a closed payment" do
      payment.update_column(:status, "closed")
      get result_path
      expect(response).to have_http_status(:ok)
    end

    it "uses the storefront layout (no admin sidebar navigation)" do
      get result_path
      # The storefront layout does not include the admin dashboard sidebar menu.
      # The dashboard layout renders a <nav> with an "admin" data attribute;
      # the storefront layout omits it.
      expect(response.body).not_to include("data-controller=\"admin_table\"")
      # Title set by the storefront layout
      expect(response.body).to include("<title>Payment</title>")
    end
  end

  # ---------------------------------------------------------------------------
  # Page → payment handoff: return leg
  # When the shopper arrived through a handoff, a succeeded payment completes
  # the invocation and redirects to the page author's configured exit_target.
  # ---------------------------------------------------------------------------
  describe "handoff return leg" do
    it "redirects to the completion target and copies the flash when a handoff completes" do
      payment.update!(status: "succeeded", paid_at: Time.current)
      allow(Payments::HandoffCompletion).to receive(:call).and_return(
        redirect_to: "/#{customer.id}/page/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        flash:       { feature_module_result: { module_key: "payment", output: { status: "succeeded" } } }
      )

      get result_path

      expect(response).to redirect_to("/#{customer.id}/page/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
      expect(flash[:feature_module_result]).to include(module_key: "payment")
    end

    it "redirects to an external url exit_target without raising an open-redirect error" do
      payment.update!(status: "succeeded", paid_at: Time.current)
      allow(Payments::HandoffCompletion).to receive(:call).and_return(
        redirect_to: "https://vendor.example/thanks",
        flash:       { feature_module_result: { module_key: "payment", output: {} } }
      )

      get result_path

      expect(response).to redirect_to("https://vendor.example/thanks")
    end

    it "renders the standalone result page when there is no handoff to complete" do
      payment.update!(status: "succeeded", paid_at: Time.current)
      allow(Payments::HandoffCompletion).to receive(:call).and_return(nil)

      get result_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payment successful")
    end

    it "uses the public root for the return link when the session belongs to another tenant" do
      payment.update!(status: "succeeded", paid_at: Time.current)
      allow_any_instance_of(Payments::ResultsController).to receive(:current_invocation)
        .and_raise(FeatureModules::CrossTenantViolation)

      get result_path

      expect(response).to have_http_status(:ok)
      expect(Capybara.string(response.body)).to have_link(I18n.t("comp_payments.result.return"), href: root_path)
    end

    it "uses a saved Return URL only while the Payments handoff switch is enabled" do
      feature_module = enable_module!("payment", customer)
      assignment = FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: feature_module)
      assignment.merge_configuration!(exit_landing_page: { kind: "url", url: "https://example.com/thanks" })
      payment.update!(status: "succeeded", paid_at: Time.current)
      feature_module.update!(handoff_enabled: false)

      get result_path
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("comp_payments.result.return"), href: "/#{customer.id}/admin/dashboard"
      )

      feature_module.update!(handoff_enabled: true)
      get result_path
      expect(Capybara.string(response.body)).to have_link(
        I18n.t("comp_payments.result.return"), href: "https://example.com/thanks"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Public — no authentication required
  # ---------------------------------------------------------------------------
  describe "public access (unauthenticated)" do
    it "renders without a signed-in user (no Devise redirect)" do
      # The controller skips authenticate_user! so anonymous users must reach it.
      get result_path
      expect(response).to have_http_status(:ok)
      expect(response).not_to be_redirect
    end
  end

  # ---------------------------------------------------------------------------
  # Cross-tenant isolation
  # Payments are scoped by customer_id; a payment belonging to customer A
  # must not be retrievable under customer B's namespace.
  # ---------------------------------------------------------------------------
  describe "cross-tenant isolation" do
    it "returns 404 when the payment_id does not belong to the customer in the URL" do
      other_customer = create(:customer)
      other_order = create(:payment_order,
        customer:     other_customer,
        external_ref: "xorder-#{SecureRandom.hex(4)}",
        amount: 5.00,
        currency:     "CNY",
        subject:      "Other order",
        status:       "pending"
      )
      other_payment = create(:payment,
        customer:      other_customer,
        payment_order: other_order,
        provider:      "alipay",
        flow:          "qr",
        out_trade_no:  "xtrade-#{SecureRandom.hex(6)}",
        amount: 5.00,
        status:        "created"
      )

      # Request other_payment under customer's namespace — Rails rescues
      # ActiveRecord::RecordNotFound and returns 404.
      get result_path(other_payment.out_trade_no)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when an anonymous caller looks up by integer primary key" do
      get result_path(payment.id)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # 404 for unknown payment_id
  # ---------------------------------------------------------------------------
  describe "unknown payment" do
    it "returns 404 for a non-existent payment_id" do
      get result_path(0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
