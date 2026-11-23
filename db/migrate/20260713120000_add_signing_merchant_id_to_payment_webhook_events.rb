# frozen_string_literal: true

# Persists the merchant_id that signed the notification (already resolved and
# used to pick the verifying MerchantAccount in WebhookDispatcher) alongside
# the event. HandleWebhook's signing_matches_payment? binding check needs this
# id to guard against a cross-merchant forgery; when the reaper cron
# (Payments::Cron::RedriveWebhookEvents) re-drives a stuck event there is no
# inbound request to re-extract it from, so it must be read back off the row.
class AddSigningMerchantIdToPaymentWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_webhook_events, :signing_merchant_id, :string
  end
end
