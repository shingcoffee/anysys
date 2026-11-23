# frozen_string_literal: true

require_relative "../data_migrations/payment_historical_bindings_v1"

# Deliberately distinct from Billing A's financial lifecycle migration.
class BackfillPaymentHistoricalBindings < ActiveRecord::Migration[8.1]
  def up
    report = PaymentHistoricalBindingsV1.new.call(apply: true)
    say "Historical payment binding data repair: #{report.fetch('summary')}"
  rescue PaymentHistoricalBindingsV1::UnresolvedBindings => error
    raise ActiveRecord::MigrationError,
          "Historical payment/event merchant evidence is unresolved: #{error.report.fetch('unresolved').to_json}. " \
          "Run payments:historical_bindings:preflight and reconcile explicit PSP/ledger evidence before retrying."
  end

  def down
    # Removing recovered identity would make already verified user records
    # unprocessable again. No money/status/number is changed by this migration.
    raise ActiveRecord::IrreversibleMigration, "historical payment identity must be preserved"
  end
end
