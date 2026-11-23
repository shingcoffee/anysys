# frozen_string_literal: true

module Payments
  module Activities
    # Initiate a card-vaulting flow via the gateway's SetupIntent API.
    #
    # Steps:
    #   1. Resolve the active gateway for the given provider/customer.
    #   2. Call gateway#vault_card to create a PSP Customer + SetupIntent.
    #   3. Persist a Payments::PaymentMethod row (status "active") with the
    #      returned psp_customer_id. brand/last4/exp are backfilled later
    #      when the setup_intent.succeeded webhook fires.
    #
    # Returns { client_secret:, payment_method: }.
    class VaultCard
      def self.call(customer:, user:, provider:, return_url:)
        result = Payments::Gateway.vault_card(
          customer: customer,
          user:     user,
          provider: provider,
          return_url: return_url
        )

        placeholder = result[:setup_intent_id].presence || SecureRandom.hex(8)
        payment_method = Payments::PaymentMethod.create!(
          customer:             customer,
          user_id:              user.id,
          provider:             provider,
          psp_customer_id:      result[:psp_customer_id],
          # Bound to the SetupIntent id when the gateway returns one so
          # setup_intent.succeeded can backfill THIS row, not the oldest
          # pending card for the same Stripe customer.
          psp_payment_method_id: "#{Payments::PaymentMethod::PENDING_TOKEN_PREFIX}#{placeholder}",
          status:               "active"
        )

        { client_secret: result[:client_secret], payment_method: payment_method }
      end
    end
  end
end
