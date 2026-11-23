# frozen_string_literal: true

require "csv"
require "bigdecimal"

module Payments
  module Gateways
    class WechatPay
      # Thin native-format adapter around Ruby's CSV parser. WeChat escapes
      # commas/newlines in merchant text itself and prefixes values with `;
      # quotes are literal vendor data, not CSV quoting. Summary rows are a
      # second table, not financial records.
      # https://pay.weixin.qq.com/doc/v3/merchant/4013071246
      class BillParser
        Result = Data.define(:records, :summary)
        REQUIRED_HEADERS = %w[交易时间 微信订单号 商户订单号 交易状态 货币种类 订单金额].freeze
        KINDS = { "SUCCESS" => "payment", "REFUND" => "refund", "REVOKED" => "reversal" }.freeze
        REFUND_STATUSES = {
          "SUCCESS" => "succeeded", "PROCESSING" => "processing",
          "FAIL" => "failed", "CHANGE" => "abnormal"
        }.freeze

        def self.call(csv)
          new(csv).call
        end

        def initialize(csv)
          @csv = csv.to_s.dup.force_encoding(Encoding::UTF_8)
        end

        def call
          raise ArgumentError unless @csv.valid_encoding?

          rows = CSV.parse(@csv.delete_prefix("\uFEFF"), quote_char: nil, skip_blanks: true).map do |row|
            row.map { |value| value.to_s.strip.delete_prefix("`") }
          end
          headers = rows.shift
          raise ArgumentError unless headers && (REQUIRED_HEADERS - headers).empty?

          summary_index = rows.index { |row| row.first == "总交易单数" }
          detail_rows = summary_index ? rows[0...summary_index] : rows
          summary = parse_summary(summary_index ? rows[summary_index..] : [])
          records = detail_rows.map do |row|
            raise ArgumentError unless row.size == headers.size

            record_for(headers.zip(row).to_h)
          end
          Result.new(records: records, summary: summary)
        rescue CSV::MalformedCSVError, ArgumentError, TypeError
          raise Payments::Errors::ApiError.new("malformed WeChat trade bill", code: "invalid_bill")
        end

        private

        def parse_summary(rows)
          return {} if rows.empty?
          raise ArgumentError unless rows.size == 2 && rows.first.size == rows.last.size

          rows.first.zip(rows.last).to_h
        end

        def record_for(row)
          kind = KINDS.fetch(row["交易状态"]) { raise ArgumentError }
          currency = row["货币种类"]
          raise ArgumentError unless currency == "CNY" && row["商户订单号"].present?

          payment = kind == "payment"
          status = payment ? "succeeded" : REFUND_STATUSES.fetch(row["退款状态"]) { raise ArgumentError }
          timestamp = payment ? row["交易时间"] : row["退款成功时间"].presence
          {
            "kind" => kind,
            "out_trade_no" => row["商户订单号"],
            "psp_transaction_id" => row["微信订单号"],
            # Compare gross order/refund amounts, not settlement amounts after
            # coupons. Refund bill states are snapshots at acceptance, not a
            # substitute for the later verified refund-result notification.
            "amount" => decimal(payment ? row["订单金额"] : row["申请退款金额"]),
            "currency" => currency,
            "status" => status,
            "settled_at" => (Time.find_zone!("Asia/Shanghai").parse(timestamp) if timestamp.present?),
            "out_refund_no" => (row["商户退款单号"] if !payment && row["商户退款单号"] != "0"),
            "psp_refund_id" => (row["微信退款单号"] if !payment && row["微信退款单号"] != "0"),
            "raw" => row
          }
        end

        def decimal(value)
          amount = BigDecimal(value.to_s, exception: false)
          raise ArgumentError unless amount&.finite? && amount >= 0

          amount
        end
      end
    end
  end
end
