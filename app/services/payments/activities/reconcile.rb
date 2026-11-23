# frozen_string_literal: true

require "csv"

module Payments
  module Activities
    class Reconcile
      def self.call(customer:, provider:, bill_date:, bill_type: "all", merchant_account: nil, payment: nil)
        if payment
          pinned = Payments::CredentialResolver.for_payment(customer: customer, payment: payment)
          if merchant_account && merchant_account.id != pinned.id
            raise Payments::Errors::TenantMismatch, "bill account does not match the payment attempt"
          end
          merchant_account = pinned
        end
        bill = Payments::ReconciliationBill.find_or_create_by!(
          customer_id: customer.id, provider: provider,
          bill_date: bill_date, bill_type: bill_type
        )
        result = download_bill(customer: customer, provider: provider, merchant_account: merchant_account,
                               bill_date: bill_date, bill_type: bill_type)
        rows = normalized_rows(result, provider)
        total = rows.sum { |r| row_amount(r) || 0 }
        bill.bill_file.attach(
          io: StringIO.new(result[:csv].to_s),
          filename: "#{provider}-#{bill_date}-#{bill_type}.csv",
          content_type: "text/csv"
        )
        summary = result[:raw_summary] || {}
        if merchant_account
          summary = summary.merge("merchant_account_id" => merchant_account.id,
                                  "merchant_id" => merchant_account.merchant_id, "mode" => merchant_account.mode)
        end
        bill.mark_parsed!(total_count: rows.size, total_amount: total, raw_summary: summary)

        # Forward: every PSP row must map to a succeeded local payment of the SAME
        # amount (amount-aware — a bill that disagrees on amount is a discrepancy,
        # not a clean match).
        forward = rows.count { |row| !row_reconciles?(customer, row, provider: provider, merchant_account: merchant_account) }

        # Reverse: local successes for this provider settled on the bill date that
        # are ABSENT from the PSP bill (money we think we captured but the PSP
        # never settled). Scoped by paid_at so unsettled/nil rows aren't counted.
        psp_refs = rows.filter_map { |r| r["out_trade_no"].presence unless r["kind"].in?(%w[refund reversal]) }
        reverse  = Payments::Payment
                     .where(customer_id: customer.id, provider: provider, status: "succeeded")
                     .where(paid_at: bill_date.beginning_of_day..bill_date.end_of_day)
                     .where.not(out_trade_no: psp_refs)
                     .to_a.count { |local| merchant_account.nil? || local.merchant_account_id == merchant_account.id }
        reverse = 0 if bill_type == "refund"

        bill.mark_reconciled!(discrepancies: forward + reverse)
        bill
      rescue Payments::Errors::Error => e
        bill&.mark_failed!
        raise e
      end

      def self.download_bill(customer:, provider:, merchant_account:, bill_date:, bill_type:)
        if merchant_account
          unless merchant_account.customer_id == customer.id && merchant_account.provider == provider
            raise Payments::Errors::TenantMismatch, "bill merchant binding mismatch"
          end
          # The facade's merchant lookup includes disabled historical accounts
          # and never substitutes the environment's current active credentials.
          Payments::Gateway.gateway_for_merchant(provider: provider, merchant_id: merchant_account.merchant_id)
            .download_bill(bill_date: bill_date, bill_type: bill_type)
        else
          Payments::Gateway.download_bill(customer: customer, provider: provider, bill_date: bill_date, bill_type: bill_type)
        end
      end
      private_class_method :download_bill

      # A PSP row reconciles when a succeeded local payment exists for its
      # out_trade_no AND (when the row carries an amount) the amounts match.
      def self.row_reconciles?(customer, row, provider:, merchant_account: nil)
        ref = row["out_trade_no"]
        return false if ref.blank?

        payment = Payments::Payment.where(customer_id: customer.id, provider: provider, out_trade_no: ref).first
        return false if payment.nil? || payment.status != "succeeded"
        return false if merchant_account && payment.merchant_account_id != merchant_account.id
        return refund_row_reconciles?(payment, row) if row["kind"] == "refund"
        return false if row["kind"] == "reversal"

        row_amt = row_amount(row)
        return false if (row["amount"].present? || row["total_amount"].present?) && row_amt.nil?
        return false if row["currency"].present? && row["currency"].to_s.upcase != payment.payment_order.currency
        row_amt.nil? || row_amt == payment.amount
      end

      # WeChat's canonical rows include refund snapshots. Compare against the
      # refund amount, not the parent payment's gross capture, without using a
      # bill snapshot to overwrite the later authenticated refund outcome.
      def self.refund_row_reconciles?(payment, row)
        refunds = Payments::Refund.where(payment_id: payment.id, customer_id: payment.customer_id)
        refund = if row["out_refund_no"].present?
          refunds.find_by(out_refund_no: row["out_refund_no"])
        elsif row["psp_refund_id"].present?
          refunds.find_by(psp_refund_id: row["psp_refund_id"])
        end
        return false unless refund && row_amount(row) == refund.amount
        return false if row["currency"].present? && row["currency"].to_s.upcase != payment.payment_order.currency
        return false if row["psp_refund_id"].present? && refund.psp_refund_id.present? && row["psp_refund_id"] != refund.psp_refund_id

        case row["status"]
        when "succeeded" then refund.status == "succeeded"
        when "processing" then refund.status.in?(%w[requested processing succeeded])
        when "failed", "abnormal" then refund.status == "failed"
        else false
        end
      end
      private_class_method :refund_row_reconciles?

      # Parse a settlement-row major-unit amount to decimal amount.
      def self.row_amount(row)
        amount = Payments::Money.from_major(row["amount"] || row["total_amount"], row["currency"].presence || "CNY")&.amount
        amount if amount&.finite?
      rescue ArgumentError
        nil
      end

      # Gateways may return canonical rows alongside the original bill file.
      # WeChat's native trade bill has localized headers, backtick-prefixed
      # values and a second summary table; only its transaction table is data.
      def self.normalized_rows(result, provider)
        return result[:rows].map { |row| row.to_h.stringify_keys } if result[:rows].is_a?(Array)
        csv = result[:csv].to_s.delete_prefix("\uFEFF")
        return CSV.parse(csv, headers: true).map(&:to_h) unless provider == "wechat_pay"

        table = CSV.parse(csv)
        headers = table.shift.to_a.map { |value| bill_value(value) }
        return [] if headers.empty?
        unless headers.intersect?(%w[out_trade_no 商户订单号]) &&
               headers.intersect?(["amount", "total_amount", "订单金额（元）", "订单金额(元)", "总金额"])
          raise Payments::Errors::TransportError, "unsupported WeChat bill headers"
        end

        rows = table.take_while do |values|
          first = bill_value(values.first)
          first.present? && !%w[总交易单数 总交易笔数].include?(first)
        end
        rows.filter_map do |values|
          row = headers.zip(values.map { |value| bill_value(value) }).to_h
          status = row["交易状态"]
          next if status.present? && !%w[SUCCESS REFUND].include?(status)
          {
            "out_trade_no" => row["out_trade_no"] || row["商户订单号"],
            "amount" => row["amount"] || row["total_amount"] || row["订单金额（元）"] ||
                        row["订单金额(元)"] || row["总金额"],
            "currency" => row["货币种类"]
          }
        end
      end
      private_class_method :normalized_rows

      def self.bill_value(value)
        value.to_s.strip.delete_prefix("`").strip
      end
      private_class_method :bill_value
    end
  end
end
