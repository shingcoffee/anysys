# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::CheckoutComponent, type: :component do
  let(:order) do
    Payments::Order.new(customer_id: 12345678, external_ref: "R1", amount: 12.34, subject: "Pro Plan", currency: "CNY")
  end
  let(:viewer) { nil }

  before do
    stub_helpers = double("helpers",
                          request: double(path: "/12345678/payments/checkout"),
                          current_user: viewer,
                         protect_against_forgery?: false)
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  it "renders the order summary" do
    render_inline(described_class.new(order: order, gateways: [ Payments::Gateways.for("alipay") ]))

    expect(page).to have_text("Pro Plan")
    expect(page).to have_text("Order #R1")
    expect(page).to have_text("12.34 CNY")
    expect(page).to have_css("section.bg-white.border.rounded-md")
  end

  it "renders zero-decimal currencies without fractional digits" do
    jpy_order = Payments::Order.new(
      external_ref: "R-JPY", amount: 1000.00, subject: "Japan Plan", currency: "JPY"
    )

    render_inline(described_class.new(order: jpy_order, gateways: []))

    expect(page).to have_text("1000 JPY")
    expect(page).not_to have_text("1000.00 JPY")
  end

  it "renders a button per eligible gateway with the default first" do
    gateways = [ Payments::Gateways.for("alipay"), Payments::Gateways.for("wechat_pay") ]
    html = render_inline(described_class.new(order: order, gateways: gateways, default_provider: "wechat_pay")).to_html

    expect(html).to include('value="wechat_pay"')
    expect(html).to include('value="alipay"')
    # default (wechat_pay) appears before alipay
    expect(html.index('value="wechat_pay"')).to be < html.index('value="alipay"')
  end

  it "submits each gateway form as a full page load, outside Turbo Drive" do
    gateways = [ Payments::Gateways.for("alipay"), Payments::Gateways.for("wechat_pay") ]
    render_inline(described_class.new(order: order, gateways: gateways))

    expect(page).to have_css("form[data-turbo='false']", count: 2)
  end

  it "keeps registry list order when no default is given" do
    gateways = [ Payments::Gateways.for("alipay"), Payments::Gateways.for("wechat_pay") ]
    html = render_inline(described_class.new(order: order, gateways: gateways, default_provider: nil)).to_html

    expect(html.index('value="alipay"')).to be < html.index('value="wechat_pay"')
  end

  it "renders an empty state when no gateways are eligible" do
    html = render_inline(described_class.new(order: order, gateways: [], default_provider: nil)).to_html

    expect(html).to match(/no payment/i)
  end

  it "surfaces form errors when provided" do
    errors = ActiveModel::Errors.new(order)
    errors.add(:provider, "must be selected")

    render_inline(described_class.new(order: order, gateways: [ Payments::Gateways.for("alipay") ], errors: errors))

    expect(page).to have_text("Provider must be selected")
    expect(page).to have_css(".bg-red-50")
  end

  describe "save-card consent before intent creation" do
    let(:viewer) { instance_double(Authentication::User, member?: true, customer_id: 12345678) }
    let(:stripe) { Payments::Gateways.for("stripe") }

    it "submits opt-in only with the Stripe form and keeps other providers separate" do
      render_inline described_class.new(order: order, gateways: [stripe, Payments::Gateways.for("alipay")])

      stripe_form = page.find('button[name="provider"][value="stripe"]').find(:xpath, "..")
      expect(stripe_form.tag_name).to eq("form")
      expect(stripe_form).to have_unchecked_field(I18n.t("comp_payments.widget_checkout.save_card"))
      expect(stripe_form).to have_css('input[type="checkbox"][name="save_card"][value="1"]')
      expect(stripe_form).to have_css('input[name="ref"][value="R1"]', visible: :all)
      expect(stripe_form).not_to have_css('input[type="hidden"][name="save_card"]', visible: :all)
      expect(page.find('button[value="alipay"]').find(:xpath, "..")).not_to have_field("save_card")
    end

    it "checks the selected gateway's capabilities even when Stripe is the default" do
      no_vault = double(key: "stripe", display_name: "Stripe", capabilities: [])
      other_tokenized = double(key: "other", display_name: "Other", capabilities: [:tokenized_cards])
      render_inline described_class.new(order: order, gateways: [no_vault, other_tokenized], default_provider: "stripe")
      expect(page).not_to have_field("save_card")
    end

    it "withholds consent for anonymous, nonmember, cross-tenant and tenantless shoppers" do
      [nil, double(member?: false), double(member?: true, customer_id: 87654321)].each do |user|
        allow_any_instance_of(described_class).to receive(:helpers).and_return(double(
          request: double(path: "/12345678/payments/checkout"), current_user: user, protect_against_forgery?: false
        ))
        render_inline described_class.new(order: order, gateways: [stripe])
        expect(page).not_to have_field("save_card")
      end
      order.customer_id = nil
      allow_any_instance_of(described_class).to receive(:helpers).and_return(double(
        request: double(path: "/12345678/payments/checkout"), current_user: viewer, protect_against_forgery?: false
      ))
      render_inline described_class.new(order: order, gateways: [stripe])
      expect(page).not_to have_field("save_card")
    end

    it "uses the existing Simplified Chinese consent label" do
      I18n.with_locale(:"zh-CN") do
        render_inline described_class.new(order: order, gateways: [stripe])
        expect(page).to have_unchecked_field("保存此卡以便日后支付")
      end
    end
  end
end
