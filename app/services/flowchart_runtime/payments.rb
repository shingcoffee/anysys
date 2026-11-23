# frozen_string_literal: true

module FlowchartRuntime
  # Payment steps for a flowchart run. request validates the money fields and
  # parks a checkout handoff on ctx[:submission_outcome]; the Payment module's
  # checkout creates the payment order from the invocation token. refund calls the
  # existing Refund activity for a payment of ctx[:customer_id] only.
  #
  # request may also name the record being paid for (+paid_record+) and what
  # changes on it once the payment succeeds: fixed +paid_fields+ values, the
  # payment time in +paid_at_field+ and the payment reference in
  # +reference_field+. Payments::PaidWriteback applies them on success,
  # whichever way the payment is confirmed.
  module Payments
    class Error < StandardError; end

    MODULE_KEY = "payment"
    DEFAULT_CURRENCY = "CNY"
    RECORD_EXIT = "record"

    module_function

    def request(ctx, amount:, currency:, subject:, description: nil, metadata: nil,
                expires_in_minutes: nil, exit_target: nil, paid_record: nil, paid_fields: nil,
                paid_at_field: nil, reference_field: nil)
      customer_id = ctx && ctx[:customer_id]
      return Step.fail(ctx, :"request_payment.invalid_order") if customer_id.blank?
      return Step.fail(ctx, :"request_payment.module_disabled") unless Handoff.available?(MODULE_KEY, customer_id)

      writeback = on_success(ctx, paid_record, paid_fields, paid_at_field, reference_field)
      return false if writeback == false

      exit_target = record_exit(ctx, paid_record) if exit_kind(exit_target) == RECORD_EXIT
      return false if exit_target == false

      currency = currency.to_s.upcase.presence || DEFAULT_CURRENCY
      subject = subject.to_s.strip
      return Step.fail(ctx, :"request_payment.invalid_order") if subject.blank?

      normalized = normalize_amount(amount, currency)
      return Step.fail(ctx, :"request_payment.invalid_order") if normalized.nil? || !normalized.positive?

      input = { "amount" => normalized, "currency" => currency, "subject" => subject }
      body = description.to_s.strip
      input["body"] = body if body.present?

      if metadata.present?
        return Step.fail(ctx, :"request_payment.invalid_order") unless metadata.respond_to?(:to_h)

        input["metadata"] = metadata.to_h.transform_keys(&:to_s)
      end

      if expires_in_minutes.present?
        minutes = Integer(expires_in_minutes, exception: false)
        return Step.fail(ctx, :"request_payment.invalid_order") unless minutes&.positive?

        input["expires_at"] = minutes.minutes.from_now.utc.iso8601
      end

      Handoff.write(ctx, module_key: MODULE_KEY, input: input, exit_target: exit_target, on_success: writeback)
      true
    end

    # What Payments::PaidWriteback writes once the payment succeeds: nil when
    # nothing is asked for, false (with the run failed) when the record or a
    # field is not one this run may write.
    def on_success(ctx, record, fields, paid_at_field, reference_field)
      fields = fields.to_h.to_h { |slug, value| [slug.to_s.strip, value.nil? ? nil : value.to_s] }.reject { |slug, _| slug.empty? }
      stamps = { "paid_at_field" => paid_at_field.to_s.strip, "reference_field" => reference_field.to_s.strip }.reject { |_, slug| slug.empty? }
      return nil if fields.empty? && stamps.empty?

      entry = paid_entry(ctx, record)
      return Step.fail(ctx, :"request_payment.invalid_paid_record") unless entry

      unknown = (fields.keys + stamps.values) - entry.valid_attribute_slugs
      return Step.fail(ctx, :"request_payment.invalid_paid_field", field_name: unknown.first) if unknown.any?

      { "entity_id" => entry.entity_id, "entry_id" => entry.id, "fields" => fields }.merge(stamps)
    end

    def record_exit(ctx, record)
      entry = paid_entry(ctx, record)
      return Step.fail(ctx, :"request_payment.invalid_paid_record") unless entry

      { "kind" => RECORD_EXIT, "entity_id" => entry.entity_id, "entry_id" => entry.id }
    end

    # A saved record of this run's tenant: the page record unless the step
    # names another.
    def paid_entry(ctx, record)
      entry = record.nil? ? ctx[:model] : record
      entry if entry.is_a?(EntityEntry) && entry.persisted? && entry.customer_id.to_s == ctx[:customer_id].to_s
    end

    def exit_kind(exit_target)
      exit_target.respond_to?(:to_h) ? exit_target.to_h.stringify_keys["kind"].to_s : ""
    end
    private_class_method :on_success, :record_exit, :paid_entry, :exit_kind

    def refund(ctx, payment:, amount: nil, reason: nil, mode: "partial")
      customer_id = ctx && ctx[:customer_id]
      return Step.fail(ctx, :"refund_payment.not_found") if customer_id.blank?

      record = owned_payment(payment, customer_id)
      return Step.fail(ctx, :"refund_payment.not_found") unless record

      refund_amount = mode.to_s == "full" ? record.amount : amount
      customer = Customer.find_by(id: customer_id)
      return Step.fail(ctx, :"refund_payment.failed") unless customer

      Current.set(customer: customer) do
        ::Payments::Activities::Refund.call(
          customer: customer,
          payment: record,
          amount: refund_amount,
          reason: reason
        )
      end
    rescue ::Payments::Errors::RefundNotAllowed => error
      details = error.details.is_a?(Hash) ? error.details.symbolize_keys : {}
      Step.fail(ctx, :"refund_payment.#{error.code}", **details)
    rescue ::Payments::Errors::Error
      Step.fail(ctx, :"refund_payment.failed")
    end

    def normalize_amount(amount, currency)
      ::Payments::Money.normalize(amount, currency)
    rescue ArgumentError
      nil
    end
    private_class_method :normalize_amount

    def owned_payment(payment, customer_id)
      if payment.is_a?(::Payments::Payment)
        return payment if payment.customer_id.to_s == customer_id.to_s

        return nil
      end

      ::Payments::Payment.for_customer(customer_id).find_by(id: payment)
    end
    private_class_method :owned_payment
  end
end
