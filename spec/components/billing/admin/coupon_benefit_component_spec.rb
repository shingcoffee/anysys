# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::CouponBenefitComponent, type: :component do
  it "shows accepted fixed-currency terms and an exhausted allowance without relabeling the discount" do
    render_inline described_class.new(currency: "USD", benefit: {
      code: "CNY500", name: "Accepted discount", discount_type: "fixed", amount_off_cents: 500,
      currency: "CNY", duration: "repeating", remaining_cycles: 0, eligible: false
    })
    expect(page).to have_text("Up to ¥5.00 off eligible charges")
    expect(page).to have_text("0 eligible billed cycles remaining")
    expect(page).to have_text("Billed-cycle allowance used up")
    expect(page).not_to have_text("$5.00")
  end

  it "accepts string-keyed facts, localizes percent terms and escapes user-authored names" do
    I18n.with_locale(:"zh-CN") do
      render_inline described_class.new(currency: "USD", benefit: {
        "code" => "FOREVER", "name" => "<script>name</script>", "discount_type" => "percent",
        "percent_off" => 20, "duration" => "forever", "remaining_cycles" => nil, "eligible" => true
      })
      expect(page).to have_text(I18n.t("comp_billing.subscription_coupon.percent_benefit", percent: 20))
      expect(page).to have_text(I18n.t("comp_billing.subscription_coupon.eligible_next"))
      expect(page).not_to have_css("script, .translation_missing")
    end
  end

  it "draws remaining-cycle progress for a repeating coupon with a cycle allowance" do
    render_inline described_class.new(currency: "USD", benefit: {
      code: "SAVE20", name: "Accepted offer", discount_type: "percent", percent_off: 20,
      duration: "repeating", duration_in_cycles: 4, remaining_cycles: 2, eligible: true
    })
    expect(page).to have_css("[aria-hidden='true'] .bg-accent[style='width: 50%']")
    expect(page).to have_text("2 eligible billed cycles remaining")
  end
end
