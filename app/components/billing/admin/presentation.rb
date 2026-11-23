# frozen_string_literal: true

module Billing
  module Admin
    # Formatting only. Eligibility, prices and provider destinations come from
    # the authorized billing queries; presentation never performs a command.
    module Presentation
      def fact(value, key)
        return if value.nil?
        if value.respond_to?(:key?)
          return value[key] if value.key?(key)
          return value[key.to_s] if value.key?(key.to_s)
          return value[key.to_sym] if key.respond_to?(:to_sym) && value.key?(key.to_sym)
          return
        end

        value.public_send(key) if value.respond_to?(key)
      end

      def billing_time(value)
        return I18n.t("common.labels.em_dash") if value.blank?

        time = I18n.l(value, format: :long)
        value.respond_to?(:zone) ? I18n.t("comp_billing.time_with_zone", time: time, zone: value.zone) : time
      end

      def billing_date(value)
        value.present? ? I18n.l(value.to_date, format: :long) : I18n.t("common.labels.em_dash")
      end

      def billing_amount(cents, currency)
        return I18n.t("common.labels.em_dash") if cents.nil? || currency.blank?

        I18n.t("comp_billing.money", amount: Billing::CurrencyResolver.format(cents, currency), currency: currency)
      end

      def snapshot_name(subscription)
        fact(fact(subscription, :plan_snapshot), :name).presence || subscription.plan&.name || I18n.t("comp_billing.plan_comparison.plan_fallback")
      end

      # Reform's public serialization preserves raw submitted properties and
      # virtual nested values without syncing them onto the persisted record.
      def form_value(field)
        record = form || (form_record if respond_to?(:form_record))
        return unless record
        return fact(record.to_nested_hash, field) if record.respond_to?(:to_nested_hash)

        record.public_send(field) if record.respond_to?(field)
      end

      def form_errors
        (form || form_record).errors
      end

      def field_errors(field)
        errors = Array(form_errors[field])
        errors += Array(form_errors[:limits]) if field.to_s.start_with?("limits.")
        errors.map(&:to_s).uniq
      end

      def submitted_options(options, field)
        value = form_value(field)
        options.any? { |_, key| key.to_s == value.to_s } || value.blank? ? options : [[value, value], *options]
      end

      def field_options(field)
        { aria: { invalid: field_errors(field).any?, describedby: field_errors(field).any? ? error_id(field) : nil } }
      end

      def error_id(field)
        "#{form_scope}_#{field.to_s.tr('.', '_')}_error"
      end

      def field_error(field)
        return if field_errors(field).empty?

        tag.p(field_errors(field).join(I18n.t("comp_billing.forms.error_separator")), id: error_id(field), class: "mt-1 text-body-sm text-danger", role: "alert")
      end

      def permitted_filters
        (filters || {}).to_h.symbolize_keys.slice(*filter_keys).reject { |_, value| value.blank? }
      end

      def filtered?
        permitted_filters.any?
      end

      def pagination_path
        page_path || ->(page) { history_path(**permitted_filters.merge(page: page, locale: I18n.locale)) }
      end
    end
  end
end
