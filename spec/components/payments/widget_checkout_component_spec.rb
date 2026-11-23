# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::WidgetCheckoutComponent, type: :component do
  # ── Shared fixtures ─────────────────────────────────────────────────────────

  let(:order) do
    Payments::Order.new(
      external_ref:  "ORD-99",
      amount: 49.99,
      subject:       "Pro Plan",
      currency:      "usd"
    )
  end

  let(:result_url) { "/99/payments/result/42" }
  let(:status_url) { "/99/payments/status/42" }

  # ── Stripe gateway descriptor ────────────────────────────────────────────────

  let(:stripe_descriptor) do
    {
      controller:         "payments--stripe-card",
      value_keys:         %i[publishable_key client_secret],
      renders_pay_button: true,
      supports_save_card: true,
      secured_by:         "Stripe"
    }
  end

  let(:stripe_gateway) do
    descriptor = stripe_descriptor
    Class.new do
      define_singleton_method(:checkout_widget) { descriptor }
    end
  end

  let(:stripe_payment) do
    Payments::Payment.new(
      id:             42,
      out_trade_no:   "ch-42",
      provider:       "stripe",
      status:         "pending",
      prepay_payload: {
        "publishable_key" => "pk_test_xyz",
        "client_secret"   => "pi_secret_abc"
      }
    )
  end

  # ── PayPal gateway descriptor ────────────────────────────────────────────────

  let(:paypal_descriptor) do
    {
      controller:         "payments--paypal-buttons",
      value_keys:         %i[client_id paypal_order_id currency],
      renders_pay_button: false,
      supports_save_card: false,
      secured_by:         "PayPal"
    }
  end

  let(:paypal_gateway) do
    descriptor = paypal_descriptor
    Class.new do
      define_singleton_method(:checkout_widget) { descriptor }
    end
  end

  let(:paypal_payment) do
    Payments::Payment.new(
      id:             43,
      out_trade_no:   "pp-43",
      provider:       "paypal",
      status:         "pending",
      prepay_payload: {
        "client_id"       => "AY_client_id",
        "paypal_order_id" => "PP-ORDER-123",
        "currency"        => "USD"
      }
    )
  end

  # ── Helper ───────────────────────────────────────────────────────────────────

  def render_stripe
    render_inline(
      described_class.new(
        order:          order,
        payment:        stripe_payment,
        gateway:        stripe_gateway,
        result_url:     result_url,
        status_url:     status_url
      )
    )
  end

  def render_paypal
    render_inline(
      described_class.new(
        order:      order,
        payment:    paypal_payment,
        gateway:    paypal_gateway,
        result_url: result_url,
        status_url: status_url
      )
    )
  end

  # ── Order summary (shared) ───────────────────────────────────────────────────

  describe "order summary" do
    before { render_stripe }

    it "renders the order subject" do
      expect(page).to have_text("Pro Plan")
    end

    it "renders the order external_ref" do
      expect(page).to have_text("ORD-99")
    end

    it "renders the formatted amount" do
      # 4999 cents → 49.99
      expect(page).to have_text("49.99")
    end

    it "renders the currency code" do
      expect(page).to have_text("USD")
    end
  end

  # ── Stripe descriptor ────────────────────────────────────────────────────────

  describe "Stripe descriptor" do
    context "with a prepared PaymentIntent" do
      before { render_stripe }

      it "mounts the payments--stripe-card Stimulus controller" do
        expect(page).to have_css("[data-controller='payments--stripe-card']")
      end

      it "injects the publishable-key value attribute" do
        expect(page).to have_css(
          "[data-payments--stripe-card-publishable-key-value='pk_test_xyz']"
        )
      end

      it "injects the client-secret value attribute" do
        expect(page).to have_css(
          "[data-payments--stripe-card-client-secret-value='pi_secret_abc']"
        )
      end

      it "injects the result-url value attribute" do
        expect(page).to have_css(
          "[data-payments--stripe-card-result-url-value='#{result_url}']"
        )
      end

      it "injects the status-url value attribute" do
        expect(page).to have_css(
          "[data-payments--stripe-card-status-url-value='#{status_url}']"
        )
      end

      it "renders the element target (widget mount point)" do
        expect(page).to have_css("[data-payments--stripe-card-target='element']")
      end

      it "renders the error target" do
        expect(page).to have_css("[data-payments--stripe-card-target='error']")
      end

      it "renders the error region with aria-live=polite" do
        expect(page).to have_css("[data-payments--stripe-card-target='error'][aria-live='polite']")
      end

      it "renders a Pay button wired to payments--stripe-card#submit" do
        expect(page).to have_css("[data-action='click->payments--stripe-card#submit']")
      end

      it "does not render the save-card checkbox" do
        expect(page).not_to have_field("save_card")
        expect(page).not_to have_text("Save this card")
      end

      it "shows a Stripe trust footer" do
        expect(page).to have_text("Secured by Stripe")
      end
    end

    context "with gateway tokenization capability" do
      before { render_stripe }

      it "does not offer consent after the PaymentIntent has already been created" do
        expect(page).not_to have_field("save_card")
      end

      it "does not imply the prepared intent can be changed by a late opt-in" do
        expect(page).not_to have_text("Save this card for future payments")
      end

      it "checkbox is unchecked by default" do
        expect(page).not_to have_css("input[name='save_card'][checked]")
      end

      it "still renders the Pay button" do
        expect(page).to have_css("[data-action='click->payments--stripe-card#submit']")
      end
    end
  end

  # ── PayPal descriptor ────────────────────────────────────────────────────────

  describe "PayPal descriptor" do
    before { render_paypal }

    it "mounts the payments--paypal-buttons Stimulus controller" do
      expect(page).to have_css("[data-controller='payments--paypal-buttons']")
    end

    it "injects the client-id value attribute" do
      expect(page).to have_css(
        "[data-payments--paypal-buttons-client-id-value='AY_client_id']"
      )
    end

    it "injects the paypal-order-id value attribute" do
      expect(page).to have_css(
        "[data-payments--paypal-buttons-paypal-order-id-value='PP-ORDER-123']"
      )
    end

    it "injects the currency value attribute" do
      expect(page).to have_css(
        "[data-payments--paypal-buttons-currency-value='USD']"
      )
    end

    it "injects the result-url value attribute" do
      expect(page).to have_css(
        "[data-payments--paypal-buttons-result-url-value='#{result_url}']"
      )
    end

    it "injects the status-url value attribute" do
      expect(page).to have_css(
        "[data-payments--paypal-buttons-status-url-value='#{status_url}']"
      )
    end

    it "renders the element target (Smart Buttons mount point)" do
      expect(page).to have_css("[data-payments--paypal-buttons-target='element']")
    end

    it "renders the error target" do
      expect(page).to have_css("[data-payments--paypal-buttons-target='error']")
    end

    it "does NOT render a Pay button (PayPal injects its own)" do
      expect(page).not_to have_css("[data-action*='paypal-buttons#submit']")
    end

    it "does NOT render a save-card checkbox" do
      expect(page).not_to have_field("save_card")
    end

    it "shows a PayPal trust footer" do
      expect(page).to have_text("Secured by PayPal")
    end
  end

  # ── Zero-decimal currency ────────────────────────────────────────────────────

  describe "formatted_amount — zero-decimal currency (JPY)" do
    let(:jpy_order) do
      Payments::Order.new(
        external_ref:  "ORD-JPY",
        amount: 5.00,   # stored as major-unit decimal → ¥5
        subject:       "JPY Item",
        currency:      "jpy"
      )
    end

    it "renders the integer amount without decimal places" do
      render_inline(
        described_class.new(
          order:      jpy_order,
          payment:    stripe_payment,
          gateway:    stripe_gateway,
          result_url: result_url,
          status_url: status_url
        )
      )
      expect(page).to have_text("5")
      expect(page).not_to have_text("5.00")
    end
  end

  # ── Accessibility ────────────────────────────────────────────────────────────

  describe "accessibility" do
    it "error region has aria-live=polite for Stripe" do
      render_stripe
      expect(page).to have_css(
        "[data-payments--stripe-card-target='error'][role='alert'][aria-live='polite']"
      )
    end

    it "error region has aria-live=polite for PayPal" do
      render_paypal
      expect(page).to have_css(
        "[data-payments--paypal-buttons-target='error'][role='alert'][aria-live='polite']"
      )
    end
  end
end
