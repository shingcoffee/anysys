# frozen_string_literal: true

# Binds a payment to the exact page → module handoff invocation that produced
# it. The token is minted per-invocation (FeatureModules::Invocation.begin!),
# carried in the session, and stamped onto the Payment at charge time so
# Payments::HandoffCompletion can complete an invocation ONLY with the payment
# charged in that same invocation — not merely any payment sharing the order's
# external_ref.
class AddHandoffTokenToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :handoff_token, :string
  end
end
