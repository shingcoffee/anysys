# frozen_string_literal: true

module Websites
  module Admin
    # Native item identity and its editing body; proof rows stay expanded.
    class ArrayItemComponent < ApplicationComponent
      HEADER_CLASS = "flex min-h-11 min-w-0 list-none items-center gap-2.5 rounded-lg px-3 py-1.5 text-sm text-text-secondary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent [&::-webkit-details-marker]:hidden"

      attr_reader :fields, :field_id, :number, :title_key

      def initialize(fields:, item:, field_id:, number: 1, title_key: "title", simple: false,
                     expanded: false, first: false, last: false, min_reached: false, max_reached: false,
                     site_pages: [], uploadable: false, workspace: false)
        @fields, @field_id, @number, @title_key = fields, field_id, number, title_key
        @item = item.respond_to?(:stringify_keys) ? item.stringify_keys : {}
        @simple, @expanded, @workspace = simple, expanded, workspace
        @site_pages, @uploadable = site_pages, uploadable
        @toolbar_options = { first: first, last: last, min_reached: min_reached, max_reached: max_reached }
      end

      def workspace?
        @workspace
      end

      def accordion?
        workspace? && !@simple
      end

      def expanded?
        @expanded
      end

      # Wide panels float the toolbar into this row, so reserve its width
      # whenever the toolbar is showing.
      def header_class
        return "#{HEADER_CLASS} @min-[21rem]/content:pr-38" unless accordion?

        "#{HEADER_CLASS} cursor-pointer hover:text-text-primary @min-[21rem]/content:group-open/item:pr-38"
      end

      def title
        @item[title_key].to_s.strip.presence || t("website.admin.pages.form.item_label_format").gsub("{number}", number.to_s)
      end

      def image?
        fields.any? { |field| field[:key] == "image_url" }
      end

      def image_url
        @item["image_url"].to_s
      end

      def previewable?
        Websites::Href.media?(image_url)
      end

      def field_rows
        return fields.map { |field| [field] } unless workspace?

        ordered = fields.sort_by { |field| field[:key] == "span" ? 1 : 0 }
        paired = @simple ? %w[label value] : %w[name role]
        ordered.each_with_object([]) do |field, rows|
          next if field[:key] == paired.last && ordered.any? { |other| other[:key] == paired.first }

          rows << (field[:key] == paired.first ? ordered.select { |other| paired.include?(other[:key]) } : [field])
        end
      end

      def prop_component(field)
        PropFieldComponent.new(
          field: field, value: @item[field[:key]], field_id: "#{field_id}_#{field[:key]}",
          site_pages: @site_pages, uploadable: @uploadable, workspace: workspace?,
          rows: (2 if field[:key] == "body"),
          option_label: ->(option) { t(SectionEditorComponent::OPTION_LABEL_KEYS.fetch(field[:key]).fetch(option)) }
        )
      end

      def toolbar
        ArrayItemToolbarComponent.new(**@toolbar_options, workspace: workspace?, number: number, title: title)
      end
    end
  end
end
