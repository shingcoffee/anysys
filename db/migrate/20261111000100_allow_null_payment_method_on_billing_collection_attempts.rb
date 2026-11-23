# frozen_string_literal: true

class AllowNullPaymentMethodOnBillingCollectionAttempts < ActiveRecord::Migration[8.1]
  def change
    change_column_null :billing_collection_attempts, :billing_payment_method_id, true
  end
end
