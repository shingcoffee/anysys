# frozen_string_literal: true

class AddPastDueAtToBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_subscriptions, :past_due_at, :datetime
  end
end
