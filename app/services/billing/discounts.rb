# frozen_string_literal: true

module Billing
  module Discounts
    module_function

    # B holds subscription -> invoice locks and finalizes in the same transaction.
    def reserve_for_invoice!(invoice:)
      raise ArgumentError, "Finalization transaction required" unless ApplicationRecord.connection.transaction_open?
      if invoice.billing_coupon_redemption_id && invoice.coupon_cycle_number
        redemption = CouponRedemption.unscoped_by_tenant.find(invoice.billing_coupon_redemption_id)
        return reservation(invoice, redemption, invoice.coupon_cycle_number)
      end
      return unless invoice.status == "draft" && %w[initial renewal].include?(invoice.purpose)
      return unless recurring_subtotal(invoice).positive?

      redemption = CouponRedemption.unscoped_by_tenant.find_by(customer_id: invoice.customer_id,
        billing_subscription_id: invoice.billing_subscription_id)
      return unless redemption
      terms = redemption.terms_snapshot
      return if terms["discount_type"] == "fixed" && terms["currency"] != invoice.currency
      maximum = case terms["duration"]
      when "once" then 1
      when "repeating" then terms.fetch("duration_in_cycles")
      when "forever" then nil
      else raise ArgumentError, "Invalid accepted coupon duration"
      end
      return if maximum && redemption.cycles_used >= maximum

      cycle = redemption.cycles_used + 1
      changed = CouponRedemption.where(id: redemption.id, cycles_used: redemption.cycles_used)
        .update_all(cycles_used: cycle, updated_at: Time.current)
      raise ActiveRecord::StaleObjectError.new(redemption, "reserve") unless changed == 1

      invoice.update!(billing_coupon_id: redemption.billing_coupon_id,
        billing_coupon_redemption_id: redemption.id, coupon_cycle_number: cycle)
      reservation(invoice, redemption, cycle)
    end

    def recurring_subtotal(invoice)
      [invoice.line_items.where(kind: "subscription").sum(:amount_cents), 0].max
    end

    def reservation(invoice, redemption, cycle)
      terms = redemption.terms_snapshot
      subtotal = recurring_subtotal(invoice)
      raw = terms["discount_type"] == "percent" ? subtotal * terms.fetch("percent_off") / 100 : terms.fetch("amount_off_cents")
      { redemption_id: redemption.id, cycle_number: cycle, discount_cents: raw.clamp(0, subtotal),
        description_key: "comp_billing.invoice_lines.discount", description_values: { name: terms.fetch("name") } }
    end
  end
end
