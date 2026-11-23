# frozen_string_literal: true

# The original default ("processed") described an abandoned design where rows
# only persisted for successfully processed events. The shipped pipeline
# always inserts "received" first (WebhookDispatcher) and only flips to
# "processed"/"failed" once ProcessWebhookEventJob finishes — "received" is
# the correct default.
class ChangePaymentWebhookEventsStatusDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :payment_webhook_events, :status, from: "processed", to: "received"
  end
end
