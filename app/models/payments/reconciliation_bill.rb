# frozen_string_literal: true

module Payments
  class ReconciliationBill < ApplicationRecord
    self.table_name = "payment_reconciliation_bills"

    include TenantScoped

    PROVIDERS  = %w[wechat_pay alipay].freeze
    BILL_TYPES = %w[all success refund].freeze
    STATUSES   = %w[downloading parsed reconciled discrepant failed].freeze

    has_one_attached :bill_file

    validates :provider,   inclusion: { in: PROVIDERS }
    validates :bill_type,  inclusion: { in: BILL_TYPES }
    validates :status,     inclusion: { in: STATUSES }
    validates :bill_date,  presence: true
    validates :customer_id, presence: true
    validates :bill_date, uniqueness: { scope: %i[customer_id provider bill_type] }

    def mark_parsed!(total_count:, total_amount:, raw_summary:)
      update!(status: "parsed", total_count:, total_amount:, raw_summary:)
    end

    def mark_reconciled!(discrepancies:)
      update!(status: discrepancies.positive? ? "discrepant" : "reconciled",
              discrepancy_count: discrepancies)
    end

    def mark_failed! = update!(status: "failed")
  end
end
