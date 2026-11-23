# frozen_string_literal: true

module Billing
  module Admin
    class CustomerPaymentMethodsComponent < PaymentMethodComponent
      def actionable?(payment_method)
        payment_method.status.in?(%w[active pending failed])
      end

      def readiness_key(payment_method)
        fact(readiness(payment_method), :reason_key).presence ||
          (ready?(payment_method) ? "settings_billing.payment_methods.readiness.active" :
            payment_method.status == "active" ? "settings_billing.payment_methods.mandate_unready" : "settings_billing.payment_methods.readiness.#{payment_method.status}")
      end

      def formatted_authorized_at(payment_method) = billing_date(payment_method.authorized_at)

      def ordered_methods
        payment_methods.sort_by { |method| %w[active pending failed removed].index(method.status) || 4 }
      end

      def active_methods
        ordered_methods.select { |method| method.status == "active" }
      end

      def inactive_methods
        ordered_methods.reject { |method| method.status == "active" }
      end

      def inactive_methods_open?
        inactive_methods.any? { |method| method.status.in?(%w[pending failed]) } || active_methods.empty?
      end

      # [[heading or nil, methods]] — active methods lead without a heading.
      def method_groups
        [[nil, active_methods], [I18n.t("settings_billing.payment_methods.other_methods"), inactive_methods]].reject { |_, methods| methods.empty? }
      end

      def no_ready_methods?
        has_methods? && (pagination.nil? || fact(pagination, :total) == payment_methods.length) &&
          payment_methods.none? { |method| ready?(method) }
      end

      def add_modal_open?
        authorization.present? || (form.present? && form_errors.any?)
      end

      def catalog_root_controller
        has_methods? && has_providers? ? "payment-method modal-dialog" : "payment-method"
      end
    end
  end
end
