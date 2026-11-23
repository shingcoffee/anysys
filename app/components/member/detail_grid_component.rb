# frozen_string_literal: true

module Member
  # 2-column <dl> grid for detail pages. Row shape:
  #   { label:, value: ->(r) {...}, format: :symbol, span: 1|2, when: ->(r) {...} }
  class DetailGridComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(rows:, record:)
      @rows   = rows
      @record = record
    end

    attr_reader :rows, :record

    def visible_rows
      rows.reject { |r| r[:when] && !r[:when].call(record) }
    end

    def cell_class(row)
      row[:span] == 2 ? "sm:col-span-2" : ""
    end

    def value_class(_row)
      "mt-1.5 break-words text-site-base"
    end

    def render_value(row)
      value = row[:value].call(record)
      Member::Formatters.format(value, row[:format] || :string)
    end
  end
end
