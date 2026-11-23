# frozen_string_literal: true

module Member
  # One section of rows hanging off a member's record (Member::RecordRows):
  # a table on wide screens, cards on narrow ones, with Add, Change and
  # Remove as the page that manages the rows allows.
  class RecordRowsComponent < ApplicationComponent
    include UsesSiteChrome

    def initialize(section:, customer:)
      @section = section
      @customer = customer
    end

    attr_reader :section

    delegate :title, :columns, :rows, :page, :record, to: :section

    def value(row, column) = row.display_text(column.slug).to_s

    def add_path = helpers.new_member_page_row_path(@customer.id, page, record: record.id)
    def change_path(row) = helpers.edit_member_page_row_path(@customer.id, page, row)
    def remove_path(row) = helpers.member_page_row_path(@customer.id, page, row)

    def remove_button(row, css)
      helpers.button_to(t("member.record_rows.remove"), remove_path(row), method: :delete, class: css,
                                                                          form: { data: { turbo_confirm: t("member.record_rows.remove_confirm") } })
    end
  end
end
