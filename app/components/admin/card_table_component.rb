# frozen_string_literal: true

module Admin
  # Shared shell for the admin dashboard's embedded "card" tables: a card
  # wrapping a horizontally-scrollable <table> with the standard `table-header`
  # thead and a colspan empty-state row. Callers pass an optional title, the
  # column headers, and whether the collection is empty (+ its empty message),
  # then yield the <tr> data rows — keeping their own per-cell markup, badges,
  # and action buttons.
  #
  # For the search / sort / filter / pagination index shell (driven by Listable),
  # use AdminTableComponent instead; this is the simpler, chrome-free variant for
  # dashboard cards.
  #
  #   <%= render Admin::CardTableComponent.new(
  #         title: t("...heading"),
  #         headers: [{ label: t("...col") }, { label: t("...amount"), align: :right }],
  #         empty: records.empty?, empty_text: t("...empty")) do %>
  #     <% records.each do |r| %><tr class="table-row">…</tr><% end %>
  #   <% end %>
  class CardTableComponent < ApplicationComponent
    # headers: array of { label:, align: :left|:right|:center|nil }. A nil/omitted
    # align matches the bespoke action columns that carried no alignment class.
    def initialize(headers:, empty:, empty_text:, title: nil)
      @headers    = headers
      @empty      = empty
      @empty_text = empty_text
      @title      = title
    end

    attr_reader :headers, :empty, :empty_text, :title

    def colspan = headers.size

    def header_class(header)
      ["px-4 py-3", alignment_class(header[:align])].reject(&:blank?).join(" ")
    end

    private

    def alignment_class(align)
      case align
      when :right  then "text-right"
      when :center then "text-center"
      when :left   then "text-left"
      end
    end
  end
end
