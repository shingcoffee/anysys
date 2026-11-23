# frozen_string_literal: true

module Member
  # Read-only table for index pages. Columns are descriptor hashes:
  #   { label:, value: ->(r) {...}, format: :symbol, align: :left|:right|:center }
  class IndexTableComponent < ApplicationComponent
    include UsesSiteChrome
    def initialize(records:, columns:, row_path:, row_label: nil, row_action: nil, customer: nil)
      @records    = records
      @columns    = columns
      @row_path   = row_path
      @row_label  = row_label
      @row_action = row_action
      @customer   = customer
    end

    attr_reader :records, :columns, :row_path, :row_action, :customer

    # Translated at render time (never at class-load) so the current locale wins.
    def row_label
      @row_label || I18n.t("common.actions.view")
    end

    def row_action?
      row_action.is_a?(Hash) && row_action[:action_key].present? && row_action[:field].present?
    end

    def row_action_href(record)
      Pages::ActionLink.path(
        customer_id: customer.respond_to?(:id) ? customer.id : customer,
        action_key: row_action[:action_key],
        prefill: { row_action[:field] => record.id }
      )
    end

    def row_action_label
      row_action[:label].presence || I18n.t("member.entity_surfaces.row_action_default")
    end

    def title_column
      columns.first
    end

    def detail_columns
      Array(columns)[1..] || []
    end

    def header_class(col)
      [chrome.table_header_class, alignment_class(col)].join(" ")
    end

    def cell_class(col)
      ["px-5 py-4 text-site-sm", alignment_class(col)].join(" ")
    end

    def render_value(record, col)
      value = col[:value].call(record)
      Member::Formatters.format(value, col[:format] || :string)
    end

    def alignment_class(col)
      case col[:align]
      when :right  then "text-right"
      when :center then "text-center"
      else              "text-left"
      end
    end
  end
end
