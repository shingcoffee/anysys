# frozen_string_literal: true

module FeatureModules
  module Payment
    # Built per request so labels resolve in the current locale. Do not freeze
    # I18n.t into a load-time constant.
    module MemberSurface
      def self.build
        vendor_label = lambda do |payment|
          Payments::Gateways.for(payment.provider).display_name
        rescue ArgumentError
          payment.provider.to_s
        end

        flow_label = lambda do |payment|
          key = payment.flow.to_s
          if Payments::Payment::FLOWS.include?(key)
            I18n.t("comp_payments.gateway_card.flows.#{key}")
          else
            key
          end
        end

        Member::Surface.new(
          key:   :payments,
          label: I18n.t("feature_modules.payment.member.label"),
          icon:  :credit_card,
          default_position: 30,
          enabled_for: ->(user) {
            FeatureModules::Module.enabled?(key: "payment", customer_id: user.customer_id)
          },
          index: Member::Surface::Index.new(
            title:    I18n.t("feature_modules.payment.member.title"),
            subtitle: I18n.t("feature_modules.payment.member.subtitle"),
            scope:    ->(user) {
              Payments::Payment
                .where(user_id: user.id, customer_id: user.customer_id)
                .includes(:payment_order)
                .order(created_at: :desc)
            },
            columns: [
              { key: :date,   label: I18n.t("feature_modules.payment.member.columns.date"),   value: ->(r) { r.created_at }, format: :date },
              { key: :vendor, label: I18n.t("feature_modules.payment.member.columns.vendor"), value: vendor_label },
              { key: :amount, label: I18n.t("feature_modules.payment.member.columns.amount"), value: ->(r) { money_major(r) }, format: :money_major, align: :right, hideable: false },
              { key: :status, label: I18n.t("feature_modules.payment.member.columns.status"), value: ->(r) { r.status }, format: :status_pill }
            ],
            empty_state: {
              headline: I18n.t("feature_modules.payment.member.empty.headline"),
              body:     I18n.t("feature_modules.payment.member.empty.body"),
              icon:     :credit_card
            },
            per_page: 20
          ),
          detail: Member::Surface::Detail.new(
            title:    ->(r) { I18n.t("feature_modules.payment.member.detail_title", out_trade_no: r.out_trade_no) },
            subtitle: ->(r) { I18n.t("feature_modules.payment.member.created", date: I18n.l(r.created_at, format: :long)) },
            meta:     ->(r) {
              { label: status_label(r),
                tone: r.status == "succeeded" ? :success : :default }
            },
            sections: [
              {
                key: :primary,
                rows: [
                  { key: :amount,     label: I18n.t("feature_modules.payment.member.columns.amount"),  value: ->(r) { money_major(r) }, format: :money_major_large, hideable: false },
                  { key: :vendor,     label: I18n.t("feature_modules.payment.member.columns.vendor"),  value: vendor_label },
                  { key: :flow,       label: I18n.t("feature_modules.payment.member.columns.flow"),    value: flow_label },
                  { key: :paid_at,    label: I18n.t("feature_modules.payment.member.columns.paid_at"), value: ->(r) { r.paid_at }, format: :datetime,
                    when: ->(r) { r.paid_at } },
                  { key: :psp_txn_id, label: I18n.t("feature_modules.payment.member.columns.psp_txn_id"),
                    value: ->(r) { r.psp_transaction_id }, format: :mono, span: 2,
                    when: ->(r) { r.psp_transaction_id.present? } }
                ]
              },
              {
                key:   :refunds,
                title: I18n.t("feature_modules.payment.member.refunds"),
                when:  ->(r) { r.payment_refunds.any? },
                list:  ->(r) {
                  r.payment_refunds.map { |x|
                    { left: I18n.l(x.created_at, format: :long), right: money_major(r, x.amount), format: :money_major }
                  }
                }
              }
            ]
          )
        )
      end

      def self.money_major(payment, amount = payment.amount)
        { amount: amount, currency: payment.payment_order&.currency }
      end
      private_class_method :money_major

      def self.status_label(payment)
        key = payment.status.to_s
        if Payments::Payment::STATUSES.include?(key)
          I18n.t("common.status.#{key}")
        else
          key
        end
      end
      private_class_method :status_label
    end
  end
end
