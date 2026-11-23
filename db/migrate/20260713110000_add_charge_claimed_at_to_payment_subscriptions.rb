# frozen_string_literal: true

# DB-agnostic re-entrancy claim for the recurring-charge cron (SQLite has no
# SELECT … FOR UPDATE SKIP LOCKED): a worker atomically claims a due
# subscription before charging; a second overlapping worker's claim UPDATE
# matches zero rows and skips it.
class AddChargeClaimedAtToPaymentSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_subscriptions, :charge_claimed_at, :datetime
  end
end
