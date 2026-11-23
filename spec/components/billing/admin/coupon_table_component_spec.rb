# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CouponTableComponent, type: :component do
  let(:percent_coupon) do
    instance_double(
      Billing::Coupon,
      id:                 1,
      code:               "SAVE20",
      name:               "Save 20%",
      discount_type:      "percent",
      percent_off:        20,
      amount_off_cents:   nil,
      duration:           "once",
      duration_in_cycles: nil,
      times_redeemed:     5,
      max_redemptions:    100,
      redeem_by:          Time.zone.local(2027, 12, 31),
      active?:            true,
      redeemable?:        true,
      currency:           "CNY"
    )
  end

  let(:amount_coupon) do
    instance_double(
      Billing::Coupon,
      id:                 2,
      code:               "FLAT50",
      name:               "Flat ¥50 Off",
      discount_type:      "amount",
      percent_off:        nil,
      amount_off_cents:   5000,
      duration:           "repeating",
      duration_in_cycles: 3,
      times_redeemed:     2,
      max_redemptions:    nil,
      redeem_by:          nil,
      active?:            true,
      redeemable?:        false,
      currency:           "CNY"
    )
  end

  let(:inactive_coupon) do
    instance_double(
      Billing::Coupon,
      id:                 3,
      code:               "OLD10",
      name:               "Old 10%",
      discount_type:      "percent",
      percent_off:        10,
      amount_off_cents:   nil,
      duration:           "forever",
      duration_in_cycles: nil,
      times_redeemed:     0,
      max_redemptions:    nil,
      redeem_by:          nil,
      active?:            false,
      redeemable?:        false,
      currency:           "CNY"
    )
  end

  before do
    stub_helpers = double(
      "helpers",
      admin_maintenance_platform_billing_coupon_path:      "/81721200/admin/maintenance/platform/billing/coupons/1",
      edit_admin_maintenance_platform_billing_coupon_path: "/81721200/admin/maintenance/platform/billing/coupons/1/edit",
      new_admin_maintenance_platform_billing_coupon_path:  "/81721200/admin/maintenance/platform/billing/coupons/new",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  def build_component(coupons = [])
    described_class.new(coupons: coupons, customer_id: "81721200")
  end

  def render_table(coupons)
    render_inline(build_component(coupons))
  end

  describe "zero state" do
    before { render_table([]) }

    it "shows empty state message and a link to create the first coupon" do
      aggregate_failures do
        expect(page).to have_text("No coupons yet.")
        expect(page).to have_link("Create the first coupon.")
      end
    end
  end

  describe "with coupons" do
    before { render_table([percent_coupon, amount_coupon, inactive_coupon]) }

    it "renders coupon codes in monospace" do
      expect(page).to have_css("th.font-mono", text: "SAVE20")
      expect(page).to have_css("th.font-mono", text: "FLAT50")
      expect(page).to have_css("th.font-mono", text: "OLD10")
    end

    it "renders coupon names" do
      expect(page).to have_text("Save 20%")
      expect(page).to have_text("Flat ¥50 Off")
      expect(page).to have_text("Old 10%")
    end

    it "renders percent discount summary" do
      expect(page).to have_text("20%")
      expect(page).to have_text("10%")
    end

    it "renders amount discount summary formatted from cents" do
      expect(page).to have_text("¥50.00")
    end

    it "renders duration label" do
      expect(page).to have_text("Once")
      expect(page).to have_text("Forever")
    end

    it "renders repeating duration with cycle count" do
      expect(page).to have_text("Repeating (3 cycles)")
    end

    it "renders redemption count with max when present" do
      expect(page).to have_text("5 / 100")
    end

    it "renders redemption count only when no max" do
      expect(page).to have_text("2")
    end

    it "renders expiry date when present" do
      expect(page).to have_text(I18n.l(Date.new(2027, 12, 31), format: :long))
    end

    it "renders dash when no expiry date" do
      expect(page).to have_text("—", count: 4)
    end

    it "renders Active badge for active coupons" do
      expect(page).to have_text("Active", count: 4)
    end

    it "renders Inactive badge for inactive coupons" do
      expect(page).to have_text("Inactive")
    end

    it "merges redeemable caption into the status cell" do
      expect(page).to have_text("Redeemable now? Yes")
      expect(page).to have_text("Redeemable now? No")
    end

    it "renders View, Edit and Archive actions for each coupon" do
      expect(page).to have_link("View", count: 6)
      expect(page).to have_link("Edit", count: 6)
      expect(page).to have_button("Archive", count: 6)
    end
  end

  describe "table headers" do
    before { render_table([percent_coupon]) }

    it "renders all expected column headers" do
      aggregate_failures do
        %w[Code Discount Duration Redemptions Expires Status].each do |header|
          expect(page).to have_css("th", text: header)
        end
      end
    end
  end

  describe "#discount_summary" do
    subject(:component) { build_component }

    it "returns percentage string for percent discount type" do
      coupon = instance_double(Billing::Coupon, discount_type: "percent", percent_off: 15)
      expect(component.discount_summary(coupon)).to eq("15%")
    end

    it "returns formatted amount for amount discount type" do
      coupon = instance_double(Billing::Coupon, discount_type: "amount", amount_off_cents: 5000, currency: "CNY")
      expect(component.discount_summary(coupon)).to eq("¥50.00 CNY")
    end

    it "formats a fixed coupon in its own currency" do
      coupon = instance_double(Billing::Coupon, discount_type: "amount", amount_off_cents: 1000, currency: "USD")
      expect(component.discount_summary(coupon)).to eq("$10.00 USD")
    end
  end

  describe "#redemption_label" do
    subject(:component) { build_component }

    it "returns count / max when max_redemptions is set" do
      coupon = instance_double(Billing::Coupon, times_redeemed: 3, max_redemptions: 50)
      expect(component.redemption_label(coupon)).to eq("3 / 50")
    end

    it "returns count only when max_redemptions is nil" do
      coupon = instance_double(Billing::Coupon, times_redeemed: 7, max_redemptions: nil)
      expect(component.redemption_label(coupon)).to eq("7")
    end
  end

  it "renders supplied 25-row pagination to reach older coupon records" do
    render_inline described_class.new(coupons: [percent_coupon], customer_id: 81721200,
      pagination: { page: 2, per_page: 25, total: 51, total_pages: 3 },
      page_path: ->(page) { "/81721200/admin/maintenance/platform/billing/coupons?page=#{page}&locale=en" })
    expect(page).to have_link(href: "/81721200/admin/maintenance/platform/billing/coupons?page=1&locale=en")
    expect(page).to have_link(href: "/81721200/admin/maintenance/platform/billing/coupons?page=3&locale=en")
    expect(page).to have_text("SAVE20")
  end
end
