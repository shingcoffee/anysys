# frozen_string_literal: true

module Billing
  class Result
    FIELDS = %i[status subscription plan_change invoice payment_method record form action reason errors].freeze
    attr_reader(*FIELDS)

    def initialize(status:, errors: {}, **attributes)
      raise ArgumentError, "Unknown result fields" if (attributes.keys - FIELDS).any?

      @status = status.to_sym
      @errors = self.class.freeze_value(errors.to_h.deep_dup)
      (FIELDS - %i[status errors]).each { |field| instance_variable_set("@#{field}", attributes[field]) }
      @action = self.class.freeze_value(@action.deep_dup) if @action
      freeze
    end

    # Acquire SQLite's write reservation BEFORE reading transition state. Row
    # locks alone do not serialize SQLite. Unique indexes remain the final guard.
    def self.transaction(record, &block)
      attempts = 0
      nested = ApplicationRecord.connection.transaction_open?
      begin
        ApplicationRecord.transaction(requires_new: true) do
          record.class.unscoped.where(id: record.id).update_all("updated_at = updated_at")
          record.reload if record.persisted?
          block.call
        end
      rescue ActiveRecord::StatementInvalid => error
        raise if nested || !error.cause.is_a?(SQLite3::BusyException) || (attempts += 1) > 3

        sleep(0.01 * attempts)
        retry
      end
    end

    # Intent and invoice preparation must commit before B can perform HTTP.
    def self.collect_after_commit(invoice)
      ActiveRecord.after_all_transactions_commit do
        # The callback only enqueues. Test fixtures may hide nonjoinable outer
        # transactions from after_all_transactions_commit; HTTP must never run
        # here. A committed draft is also recovered by the cron population.
        FinalizeInvoiceJob.perform_later(invoice.id)
      end
    end

    def self.invalid(reason, **attributes)
      new(status: :invalid, reason: reason, **attributes)
    end

    def self.freeze_value(value)
      case value
      when Hash then value.each { |key, item| freeze_value(key); freeze_value(item) }
      when Array then value.each { |item| freeze_value(item) }
      end
      value.freeze
    end
  end
end
