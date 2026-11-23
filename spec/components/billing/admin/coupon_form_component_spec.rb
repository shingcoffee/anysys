# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CouponFormComponent, type: :component do
  let(:new_coupon) { Billing::Coupon.new }

  let(:persisted_coupon) do
    persist!(Billing::Coupon.new(
      code: "SAVE20", name: "Save 20%",
      discount_type: "percent", percent_off: 20,
      currency: "CNY", duration: "once",
      active: true
    ), id: 5)
  end

  # Marks an unsaved AR instance as persisted with the given id, so the form
  # component takes its edit (PATCH) branch without hitting the database.
  def persist!(record, id:)
    record.id = id
    record.instance_variable_set(:@new_record, false)
    record
  end

  def build_component(coupon)
    described_class.new(coupon: coupon, customer_id: "81721200")
  end

  def render_form(coupon)
    render_inline(build_component(coupon))
  end

  before do
    stub_helpers = double(
      "helpers",
      admin_maintenance_platform_billing_coupons_path: "/81721200/admin/maintenance/platform/billing/coupons",
      admin_maintenance_platform_billing_coupon_path:  "/81721200/admin/maintenance/platform/billing/coupons/5",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  describe "new coupon form" do
    before { render_form(new_coupon) }

    it "renders New Coupon heading" do
      expect(page).to have_text("New Coupon")
    end

    it "renders Create Coupon submit button" do
      expect(page).to have_button("Create Coupon")
    end

    it "renders discount_type select usable without JavaScript" do
      expect(page).to have_css("select[name='billing_coupon[discount_type]']")
    end

    it "renders duration select usable without JavaScript" do
      expect(page).to have_css("select[name='billing_coupon[duration]']")
    end

    it "renders percent_off field (visible by default)" do
      expect(page).to have_field("billing_coupon[percent_off]")
    end

    it "keeps inactive discount inputs visible for correction and server validation" do
      expect(page).to have_field("billing_coupon[amount_off_cents]")
    end

    it "renders active checkbox" do
      expect(page).to have_field("billing_coupon[active]")
    end
  end

  describe "data-controller attribute" do
    before { render_form(new_coupon) }

    it "wires the existing Stimulus controller for progressive enhancement" do
      aggregate_failures do
        expect(page).to have_css("[data-controller='billing-coupon-form']")
        expect(page).to have_css("[data-billing-coupon-form-discount-type-value='percent']")
        expect(page).to have_css("[data-billing-coupon-form-duration-value='once']")
        expect(page).to have_css("[data-billing-coupon-form-target='percentField']")
        expect(page).to have_css("[data-billing-coupon-form-target='fixedField']", count: 2)
        expect(page).to have_css("[data-billing-coupon-form-target='cyclesField']")
        expect(page).to have_css("[data-action='change->billing-coupon-form#discountTypeChanged']")
        expect(page).to have_css("[data-action='change->billing-coupon-form#durationChanged']")
      end
    end

    it "keeps progressive-enhancement targets visible for no-JS users" do
      expect(page).not_to have_css("[data-billing-coupon-form-target].hidden")
      expect(page).not_to have_css("[data-billing-coupon-form-target='percentField'].hidden")
      expect(page).not_to have_css("[data-billing-coupon-form-target='fixedField'].hidden")
      expect(page).not_to have_css("[data-billing-coupon-form-target='cyclesField'].hidden")
    end
  end

  describe "edit coupon form" do
    before { render_form(persisted_coupon) }

    it "renders Edit Coupon heading" do
      expect(page).to have_text("Edit Coupon")
    end

    it "renders Update Coupon submit button" do
      expect(page).to have_button("Update Coupon")
    end

    it "disables the code field" do
      code_field = page.find_field("billing_coupon[code]", disabled: true)
      expect(code_field).to be_disabled
    end
  end

  describe "repeating coupon" do
    let(:repeating_coupon) do
      persist!(Billing::Coupon.new(
        code: "REPEAT3", name: "3 months",
        discount_type: "percent", percent_off: 10,
        currency: "CNY", duration: "repeating", duration_in_cycles: 3,
        active: true
      ), id: 6)
    end

    it "shows cycles field (not hidden) for repeating coupon" do
      render_form(repeating_coupon)
      expect(page).not_to have_css("[data-billing-coupon-form-target='cyclesField'].hidden")
    end
  end

  describe "form_method" do
    it "returns :post for new coupon" do
      expect(build_component(new_coupon).form_method).to eq(:post)
    end

    it "returns :patch for persisted coupon" do
      expect(build_component(persisted_coupon).form_method).to eq(:patch)
    end
  end

  it "preserves invalid fixed amount, blank currency, inactive values and expiration from Reform" do
    form = Billing::Contracts::Coupon.new(new_coupon)
    form.discount_type = "fixed"
    form.amount_off_cents = "12.5"
    form.percent_off = "bad-percent"
    form.currency = ""
    form.redeem_by = "not-a-date"
    form.errors.add(:currency, "is invalid")
    render_inline described_class.new(coupon: new_coupon, customer_id: 81721200, form: form)
    expect(page).to have_field("billing_coupon[amount_off_cents]", with: "12.5")
    expect(page).to have_field("billing_coupon[percent_off]", with: "bad-percent")
    expect(page).to have_field("billing_coupon[currency]", with: "")
    expect(page).to have_field("billing_coupon[redeem_by]", with: "not-a-date")
    expect(page).to have_css('input[aria-describedby="billing_coupon_currency_error"][aria-invalid="true"]')
    expect(page).to have_text("eligible billed cycles after redemption")
  end
end
