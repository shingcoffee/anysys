# frozen_string_literal: true

require "csv"

module Emails
  module Analytics
    class ExportCsv
      MAX_ROWS = 100

      def self.call(messages)
        new(messages).call
      end

      def initialize(messages)
        @messages = messages
      end

      def call
        CSV.generate(headers: true) do |csv|
          csv << %w[id to subject status sent_at delivered_at opened clicked]
          rows.each do |m|
            csv << [m.id, m.to, m.subject, m.status, m.sent_at, m.delivered_at, m.opens_count, m.clicks_count]
          end
        end
      end

      private

      def rows
        @messages.order(created_at: :desc, id: :desc).limit(MAX_ROWS)
      end
    end
  end
end
