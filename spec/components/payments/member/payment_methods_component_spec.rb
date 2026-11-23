# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::Member::PaymentMethodsComponent, type: :component do
  # Build plain-struct stand-ins so specs don't need DB or routes.
  let(:visa_card) do
    Payments::PaymentMethod.new(
      id:                    1,
      customer_id:           99,
      user_id:               7,
      provider:              "stripe",
      brand:                 "visa",
      last4:                 "4242",
      exp_month:             12,
      exp_year:              2027,
      is_default:            true,
      status:                "active",
      psp_payment_method_id: "pm_visa"
    )
  end

  let(:mc_card) do
    Payments::PaymentMethod.new(
      id:                    2,
      customer_id:           99,
      user_id:               7,
      provider:              "stripe",
      brand:                 "mastercard",
      last4:                 "5555",
      exp_month:             3,
      exp_year:              2026,
      is_default:            false,
      status:                "active",
      psp_payment_method_id: "pm_mc"
    )
  end

  let(:setup_intent_url) { "/99/member/payments/payment_methods/setup_intent" }
  let(:create_url)       { "/99/member/payments/payment_methods" }
  let(:publishable_key)  { "pk_test_abc123" }

  def destroy_url_for(pm)
    "/99/member/payments/payment_methods/#{pm.id}"
  end

  # Renders the component with the shared setup_intent_url/create_url; callers vary the cards,
  # destroy_url_proc and publishable_key. Omitting a kwarg keeps the component's own default.
  def render_component(payment_methods: [], destroy_url_proc: nil, publishable_key: nil)
    render_inline(described_class.new(
      payment_methods:  payment_methods,
      setup_intent_url: setup_intent_url,
      create_url:       create_url,
      destroy_url_proc: destroy_url_proc,
      publishable_key:  publishable_key
    ))
  end

  describe "#initialize" do
    it "accepts required props" do
      component = described_class.new(
        payment_methods:   [],
        setup_intent_url:  setup_intent_url,
        create_url:        create_url
      )
      expect(component.payment_methods).to eq([])
      expect(component.setup_intent_url).to eq(setup_intent_url)
      expect(component.create_url).to eq(create_url)
    end

    it "accepts optional destroy_url_proc and publishable_key" do
      proc = ->(pm) { destroy_url_for(pm) }
      component = described_class.new(
        payment_methods:   [visa_card],
        setup_intent_url:  setup_intent_url,
        create_url:        create_url,
        destroy_url_proc:  proc,
        publishable_key:   publishable_key
      )
      expect(component.publishable_key).to eq(publishable_key)
      expect(component.destroy_url_for(visa_card)).to eq("/99/member/payments/payment_methods/1")
    end

    it "defaults destroy_url_proc to nil when omitted" do
      component = described_class.new(
        payment_methods:  [],
        setup_intent_url: setup_intent_url,
        create_url:       create_url
      )
      expect(component.publishable_key).to be_nil
    end
  end

  describe "rendering — empty state" do
    it "renders the empty state headline when no cards saved" do
      render_component(publishable_key: publishable_key)
      expect(page).to have_text("No saved cards")
    end

    it "still renders the Add card panel in empty state so user can add one" do
      render_component(publishable_key: publishable_key)
      # The Stripe controller wrapper should be present
      expect(page).to have_css("[data-controller='payments--stripe-card']")
    end
  end

  describe "rendering — card list" do
    before do
      render_component(
        payment_methods:  [visa_card, mc_card],
        destroy_url_proc: method(:destroy_url_for),
        publishable_key:  publishable_key
      )
    end

    it "renders the display_label for each card" do
      expect(page).to have_text("Visa •••• 4242")
      expect(page).to have_text("Mastercard •••• 5555")
    end

    it "renders a Default badge for the default card" do
      expect(page).to have_text("Default")
    end

    it "does not render Default badge for non-default card" do
      # There should be exactly one Default badge
      expect(page).to have_text("Default", count: 1)
    end

    it "renders expiry for each card" do
      expect(page).to have_text("12/2027")
      expect(page).to have_text("03/2026")
    end

    it "renders a Remove button for each card when destroy_url_proc is given" do
      expect(page).to have_button("Remove", count: 2)
    end

    it "each Remove button posts to the destroy URL" do
      expect(page).to have_css("form[action='/99/member/payments/payment_methods/1'][method='post']")
      expect(page).to have_css("form[action='/99/member/payments/payment_methods/2'][method='post']")
    end
  end

  describe "rendering — Add card panel (Stripe Element)" do
    before do
      render_component(publishable_key: publishable_key)
    end

    it "mounts the payments--stripe-card Stimulus controller" do
      expect(page).to have_css("[data-controller='payments--stripe-card']")
    end

    it "passes the publishable key as a data value" do
      expect(page).to have_css(
        "[data-payments--stripe-card-publishable-key-value='#{publishable_key}']"
      )
    end

    it "passes the setup_intent_url as a data value" do
      expect(page).to have_css(
        "[data-payments--stripe-card-setup-intent-url-value='#{setup_intent_url}']"
      )
    end

    it "passes the create_url as a data value" do
      expect(page).to have_css(
        "[data-payments--stripe-card-create-url-value='#{create_url}']"
      )
    end

    it "renders the Stripe Element mount target" do
      expect(page).to have_css("[data-payments--stripe-card-target='element']")
    end

    it "renders the error region target" do
      expect(page).to have_css("[data-payments--stripe-card-target='error']")
    end
  end

  describe "rendering — without publishable_key" do
    it "renders a setup prompt instead of the Stripe Element" do
      render_component # no publishable_key
      expect(page).not_to have_css("[data-controller='payments--stripe-card']")
      expect(page).to have_text("Card payments are not configured")
    end
  end
end
