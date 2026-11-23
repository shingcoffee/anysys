# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::PaymentMethod, type: :model do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }

  # Pure keyword-splat helper (no leading positional hash) — safe against Ruby 3
  # bare-hash-as-keywords swallowing; callers always pass keywords.
  def create_pm(**attrs)
    described_class.create!(
      { customer_id: customer.id, user_id: 1, provider: "alipay" }.merge(attrs)
    )
  end

  it "requires customer_id and user_id" do
    # Bypass Current.customer so TenantScoped callback doesn't auto-fill customer_id
    Current.customer = nil
    pm = described_class.new(provider: "alipay", psp_payment_method_id: "pm_1")
    expect(pm).not_to be_valid
    expect(pm.errors.attribute_names).to include(:customer_id, :user_id)
  ensure
    Current.customer = customer
  end

  it "requires provider and psp_payment_method_id" do
    pm = described_class.new(customer_id: customer.id, user_id: 1)
    expect(pm).not_to be_valid
    expect(pm.errors.attribute_names).to include(:provider, :psp_payment_method_id)
  end

  it "rejects an unknown provider" do
    pm = described_class.new(customer_id: customer.id, user_id: 1,
                             provider: "unknown_gw", psp_payment_method_id: "pm_1")
    expect(pm).not_to be_valid
    expect(pm.errors[:provider]).to be_present
  end

  it "exposes a display label" do
    pm = described_class.new(brand: "visa", last4: "4242")
    expect(pm.display_label).to eq("Visa •••• 4242")
  end

  it "display label handles nil brand gracefully" do
    pm = described_class.new(last4: "9999")
    expect(pm.display_label).to eq("•••• 9999")
  end

  it "localizes known card brands instead of titleizing the PSP key" do
    pm = described_class.new(brand: "unionpay", last4: "0000")
    expect(pm.display_label).to eq("Unionpay •••• 0000")
    I18n.with_locale(:"zh-CN") do
      expect(pm.display_label).to eq("银联 •••• 0000")
    end
  end

  it "does not titleize an unknown brand key" do
    pm = described_class.new(brand: "foo_bar", last4: "1111")
    expect(pm.display_label).to eq("foo_bar •••• 1111")
  end

  it "NEVER has a column that could hold raw card data" do
    forbidden = %w[pan card_number cardnumber cvv cvc cvv2 security_code]
    expect(described_class.column_names & forbidden).to be_empty
  end

  it "does NOT auto-demote other defaults on save (no callback — the model is intentionally thin)" do
    pm1 = create_pm(psp_payment_method_id: "pm_a", is_default: true)
    pm2 = create_pm(psp_payment_method_id: "pm_b", is_default: false)

    # Direct update does NOT demote pm1 — the model is intentionally thin.
    pm2.update!(is_default: true)
    expect(pm1.reload.is_default).to be(true)   # still true — no callback
    expect(pm2.reload.is_default).to be(true)
  end

  it "mark_removed! sets status to removed and clears default flag" do
    pm = create_pm(psp_payment_method_id: "pm_c", is_default: true)
    pm.mark_removed!
    expect(pm.reload.status).to eq("removed")
    expect(pm.reload.is_default).to be(false)
  end

  it ".active scope returns only active records" do
    pm_active  = create_pm(psp_payment_method_id: "pm_d", status: "active")
    pm_removed = create_pm(psp_payment_method_id: "pm_e", status: "removed")
    results = described_class.active
    expect(results).to include(pm_active)
    expect(results).not_to include(pm_removed)
  end

  it ".for_user scope filters by user_id" do
    pm_mine   = create_pm(user_id: 42, psp_payment_method_id: "pm_f")
    pm_theirs = create_pm(user_id: 99, psp_payment_method_id: "pm_g")
    results = described_class.for_user(42)
    expect(results).to include(pm_mine)
    expect(results).not_to include(pm_theirs)
  end

  describe "chargeability (guards off-session charges against unusable cards)" do
    it "is chargeable when active and confirmed (real token)" do
      pm = create_pm(psp_payment_method_id: "pm_real", status: "active")
      expect(pm.confirmed?).to be(true)
      expect(pm.chargeable?).to be(true)
    end

    it "is NOT chargeable while the token is still a pending vault placeholder" do
      pm = create_pm(psp_payment_method_id: "pending:abc123", status: "active")
      expect(pm.confirmed?).to be(false)
      expect(pm.chargeable?).to be(false)
    end

    it "is NOT chargeable once removed" do
      pm = create_pm(psp_payment_method_id: "pm_real2", status: "removed")
      expect(pm.chargeable?).to be(false)
    end

    it ".chargeable scope excludes pending placeholders and removed cards" do
      good    = create_pm(psp_payment_method_id: "pm_good",    status: "active")
      pending = create_pm(psp_payment_method_id: "pending:x",  status: "active")
      removed = create_pm(psp_payment_method_id: "pm_gone",    status: "removed")
      results = described_class.chargeable
      expect(results).to include(good)
      expect(results).not_to include(pending, removed)
    end
  end
end
