# frozen_string_literal: true

module FeatureModules
  module Payment
    class Registration < FeatureModules::BaseModule
      def self.module_key         = "payment"
      def self.module_name        = "Payments"
      def self.module_description = "Accept payments across pluggable gateways — charge, refund, reconciliation, subscriptions"

      def self.provision!(customer)   = FeatureModules::Payment::Provisioner.call(customer)
      def self.deprovision!(customer) = FeatureModules::Payment::Provisioner.revoke(customer)

      entry_path   { |customer| "/#{customer.id}/payments/checkout/start" }
      default_exit kind: "route", name: "customer_home"
      handoff_entry_i18n "comp_payments.handoff_entry"

      # external_ref is NOT author-mapped: the order's reference is derived
      # server-side from the per-invocation token at checkout time (see
      # Payments::CheckoutsController#build_order_from), which also secures
      # completion. Authors only supply the money + display fields.
      input_contract do
        # CNY is rounded half-up to fen. Smaller positive amounts become zero.
        property :amount, type: :number,  validates: { presence: true, numericality: { greater_than_or_equal_to: 0.005 } }
        property :currency,     type: :enum,     validates: { presence: true, inclusion: { in: %w[CNY] } }
        property :subject,      type: :string,   validates: { presence: true }
        # Optional payer note — safe to let the end user supply/edit on the
        # checkout entry step (non-monetary, not identity). All money + identity
        # fields stay author_only so the price can never be user-supplied.
        property :body,         type: :string,   source: :user_fillable
        property :expires_at,   type: :datetime
        property :metadata,     type: :hash
      end

      input_contract_class.validate do
        normalized = ::Payments::Money.normalize(amount, currency)
        errors.add(:amount, :greater_than, count: 0) unless normalized.positive?
      rescue ArgumentError, TypeError
        errors.add(:amount, :not_a_number)
      end

      output_contract do
        property :payment_reference, validates: { presence: true }
        property :status,            validates: { inclusion: { in: %w[succeeded failed] } }
        property :paid_at
      end

      def self.sidebar_contributions(_controller)
        {
          entries: [
            ModuleContribution.new(
              label: I18n.t("feature_modules.payment.entries.transactions"),
              entry_key: "transactions",
              path: ->(cid) { "/#{cid}/admin/modules/payments/transactions" }
            ),
            ModuleContribution.new(
              label: I18n.t("feature_modules.payment.entries.reconciliations"),
              entry_key: "reconciliations",
              path: ->(cid) { "/#{cid}/admin/modules/payments/reconciliations" },
              permitted_by: :admin_or_owner?
            ),
            ModuleContribution.new(
              label: I18n.t("feature_modules.payment.entries.disputes"),
              entry_key: "disputes",
              path: ->(cid) { "/#{cid}/admin/modules/payments/disputes" }
            )
          ],
          settings: [
            ModuleContribution.new(
              label: I18n.t("feature_modules.payment.settings.merchant_accounts"),
              entry_key: "merchant_accounts",
              path: ->(cid) { "/#{cid}/admin/settings/modules/payments/merchant_accounts" },
              permitted_by: :admin_or_owner?
            )
          ]
        }
      end

      def self.entries_for(entry_key:, params:)
        case entry_key
        when "transactions"
          {
            title: I18n.t("feature_modules.payment.titles.transactions"),
            columns: [
              { key: :action, label: I18n.t("common.labels.action"), sortable: true, searchable: true },
              { key: :status, label: I18n.t("common.labels.status"), sortable: true },
              { key: :created_at, label: I18n.t("common.labels.at"), sortable: true }
            ],
            # MUST be tenant-scoped: TenantScoped installs NO default_scope, and
            # ModuleEntriesResolver adds none, so an unscoped relation here would
            # render EVERY tenant's payment logs to any customer admin. for_current_customer
            # pins the rows to Current.customer (set by TenantContext before this runs).
            scope: FeatureModules::Log.for_current_customer
                     .where(feature_module_id: FeatureModules::Module.where(key: "payment"))
                     .order(created_at: :desc)
          }
        else
          raise ArgumentError, "unknown entry_key: #{entry_key}"
        end
      end
    end
  end
end
