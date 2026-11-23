# frozen_string_literal: true

class AddAmountColumnsToPaymentTables < ActiveRecord::Migration[8.1]
  def up
    replace_integer_with_decimal(:payment_orders, :amount, :amount_cents)
    replace_integer_with_decimal(:payments, :amount, :amount_cents)
    replace_integer_with_decimal(:payment_refunds, :amount, :amount_cents)
    replace_integer_with_decimal(:payment_subscriptions, :amount, :amount_cents)
    replace_integer_with_decimal(:payment_disputes, :amount, :amount_cents, default: 0.00)
    replace_integer_with_decimal(:payment_reconciliation_bills, :total_amount, :total_amount_cents, default: 0.00)
  end

  def down
    replace_decimal_with_integer(:payment_orders, :amount_cents, :amount)
    replace_decimal_with_integer(:payments, :amount_cents, :amount)
    replace_decimal_with_integer(:payment_refunds, :amount_cents, :amount)
    replace_decimal_with_integer(:payment_subscriptions, :amount_cents, :amount)
    replace_decimal_with_integer(:payment_disputes, :amount_cents, :amount, default: 0)
    replace_decimal_with_integer(:payment_reconciliation_bills, :total_amount_cents, :total_amount, default: 0)
  end

  private

  def replace_integer_with_decimal(table, new_column, old_column, default: nil)
    add_column table, new_column, :decimal, precision: 12, scale: 2, default: default
    execute <<-SQL.squish
      UPDATE #{table}
      SET #{new_column} = #{old_column} / 100.0
      WHERE #{old_column} IS NOT NULL
    SQL
    change_column_default table, new_column, nil if default && default != 0.00
    change_column_null table, new_column, false
    remove_column table, old_column
  end

  def replace_decimal_with_integer(table, old_column, new_column, default: nil)
    add_column table, old_column, :integer, default: default
    execute <<-SQL.squish
      UPDATE #{table}
      SET #{old_column} = CAST(ROUND(#{new_column} * 100) AS INTEGER)
      WHERE #{new_column} IS NOT NULL
    SQL
    change_column_null table, old_column, false
    remove_column table, new_column
  end
end
