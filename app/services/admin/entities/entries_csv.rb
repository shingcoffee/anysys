# frozen_string_literal: true

require "csv"

module Admin
  module Entities
    class EntriesCsv
      def self.call(rows:, columns:)
        new(rows: rows, columns: columns).call
      end

      def initialize(rows:, columns:)
        @rows = rows
        @columns = columns
      end

      def call
        CSV.generate(headers: true) do |csv|
          csv << @columns.map { |c| safe_text(c[:label]) }
          @rows.each do |row|
            csv << @columns.map { |c| cell_for(row, c) }
          end
        end
      end

      private

      def cell_for(row, column)
        value = if column[:cell].respond_to?(:call)
                  column[:cell].call(row)
                elsif row.respond_to?(column[:key])
                  row.public_send(column[:key])
                else
                  row[column[:key]]
                end
        value.is_a?(Numeric) ? value.to_s : safe_text(value)
      end

      def safe_text(value)
        text = value.to_s
        text.match?(/\A[\s\uFEFF]*[=+\-@]|\A[\t\r\n]/) ? "'#{text}" : text
      end
    end
  end
end
