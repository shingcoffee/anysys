# frozen_string_literal: true

module Billing
  module Proration
    module_function

    def credit_and_charge(subscription:, new_plan:, at: Time.current)
      start = subscription.current_period_start.to_r
      finish = subscription.current_period_end.to_r
      fraction = finish <= start ? 0 : ((finish - at.to_r) / (finish - start)).clamp(0, 1)
      credit = -(subscription.amount_cents * fraction).floor
      charge = (new_plan.price_cents_for(subscription.currency) * fraction).floor
      [
        { description: I18n.t("comp_billing.invoice_lines.unused_time", name: subscription.plan_snapshot.fetch("name")),
          amount_cents: credit, unit_amount_cents: credit, quantity: 1, kind: "proration" },
        { description: I18n.t("comp_billing.invoice_lines.remaining_time", name: new_plan.name),
          amount_cents: charge, unit_amount_cents: charge, quantity: 1, kind: "proration" }
      ]
    end
  end
end
