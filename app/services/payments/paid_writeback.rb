# frozen_string_literal: true

module Payments
  # Applies the record changes a page asked for once its payment succeeds
  # (FlowchartRuntime::Payments.request parks them on the order's on_success):
  # fixed field values, the payment time and the payment reference, written
  # through Entries::Save to the paid record in the order's own tenant.
  #
  # Payments::Payment#mark_succeeded! calls it when the order first becomes
  # paid, so it runs once whichever way the payment is confirmed (result page,
  # webhook, status query). A refused write is logged and rolled back on its
  # own; the payment stays recorded.
  class PaidWriteback
    LOG_TAG = "[payments.paid_writeback]"

    def self.call(...) = new(...).call

    def initialize(payment:)
      @payment = payment
      @order = payment.payment_order
    end

    def call
      plan = @order.on_success.to_h
      return false if plan.blank?

      customer = Customer.find_by(id: @order.customer_id)
      return failed("customer #{@order.customer_id} not found") unless customer

      Current.set(customer: customer) { write(plan) }
    end

    private

    # Its own savepoint, so a refused write never undoes the settled payment
    # around it.
    def write(plan)
      entry = paid_entry(plan)
      return failed("record #{plan['entry_id']} not found") unless entry

      result = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        FlowchartRuntime::Entries.assign(entry, attributes(entry, plan), strict: true)
        result = Entries::Save.call(contract: Entries::Save::Written.new(model: entry), audience: Entities::Lifecycle::SYSTEM)
        raise ActiveRecord::Rollback unless result.ok?
      end
      result.ok? || failed(result.errors.to_sentence)
    rescue FlowchartRuntime::Entries::Error, ActiveRecord::ActiveRecordError => e
      failed("#{e.class}: #{e.message}")
    end

    def paid_entry(plan)
      entity = Entity.find_by(id: plan["entity_id"])
      return unless entity && FlowchartRuntime::EntityResolver.accessible?(entity.id, customer_id: @order.customer_id)

      EntityEntry.build_for(entity).find_by(id: plan["entry_id"], customer_id: @order.customer_id, entity_id: entity.id)
    end

    def attributes(entry, plan)
      values = plan["fields"].to_h.dup
      values[plan["paid_at_field"]] = paid_at_for(entry, plan["paid_at_field"]) if plan["paid_at_field"].present?
      values[plan["reference_field"]] = @payment.out_trade_no if plan["reference_field"].present?
      values
    end

    # Stored the way that field's form input writes it.
    def paid_at_for(entry, slug)
      at = (@payment.paid_at || Time.current).in_time_zone
      case html_type(entry, slug)
      when "date" then at.to_date.iso8601
      when "datetime-local" then at.strftime("%Y-%m-%dT%H:%M")
      else at.iso8601
      end
    end

    def html_type(entry, slug)
      attribute = Array(entry.class.bound_entity&.property_schema_json).find do |row|
        row.is_a?(Hash) && row["name_slug"].to_s == slug.to_s
      end
      attribute && attribute["html_type"].to_s
    end

    def failed(reason)
      Rails.logger.warn("#{LOG_TAG} order=#{@order.id} payment=#{@payment.id}: #{reason}")
      false
    end
  end
end
