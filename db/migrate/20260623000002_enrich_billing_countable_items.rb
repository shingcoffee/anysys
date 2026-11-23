# frozen_string_literal: true

class EnrichBillingCountableItems < ActiveRecord::Migration[8.1]
  # Registry items whose period is NOT "total" — these must be updated after the
  # column is added (all existing rows get the DB default "total" at DDL time).
  MONTHLY_KEYS = %w[email sms payment support].freeze

  def up
    add_column :billing_countable_items, :description, :text
    add_column :billing_countable_items, :unit,        :string
    add_column :billing_countable_items, :category,    :string
    add_column :billing_countable_items, :period,      :string, null: false, default: "total"

    # Backfill period for items whose registry default is "monthly" (the DB
    # default of "total" is wrong for them).
    Billing::CountableItem.where(key: MONTHLY_KEYS).update_all(period: "monthly")

    # Remove the now-obsolete flowchart item and its plan limits (idempotent).
    flowchart = Billing::CountableItem.find_by(key: "flowchart")
    if flowchart
      Billing::PlanLimit.where(item_key: "flowchart").delete_all
      flowchart.delete
    end
  end

  def down
    # Data deletion of the flowchart row is not reversible.
    remove_column :billing_countable_items, :period
    remove_column :billing_countable_items, :category
    remove_column :billing_countable_items, :unit
    remove_column :billing_countable_items, :description
  end
end
