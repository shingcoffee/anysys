# frozen_string_literal: true

module Websites
  module Sections
    # Asymmetric editorial plates with short captions (Kinfolk / Cereal).
    # Rows cycle 7+5, 5+7, 4+4+4 on a 12-column grid; plates in a row share a
    # height so the edges line up.
    class GalleryComponent < Websites::SectionComponent
      ROWS = [
        %w[md:col-span-7 md:col-span-5],
        %w[md:col-span-5 md:col-span-7],
        %w[md:col-span-4 md:col-span-4 md:col-span-4]
      ].freeze

      def items
        list("items")
      end

      def plates
        queue = items.each_with_index.to_a
        rows = []
        ROWS.cycle do |spans|
          break if queue.empty?

          row = queue.shift(spans.size)
          spans = row.size == spans.size ? spans : fallback_spans(row.size)
          rows << row.zip(spans).map { |(item, index), span| { item: item, index: index, span: span, triple: spans.size == 3 } }
        end
        rows.flatten
      end

      def plate_height_class(plate)
        plate[:triple] ? "aspect-[4/5] md:aspect-auto md:h-[22rem] lg:h-[26rem]" : "aspect-[4/3] md:aspect-auto md:h-[26rem] lg:h-[32rem]"
      end

      private

      def fallback_spans(count)
        count == 1 ? %w[md:col-span-12] : %w[md:col-span-6 md:col-span-6]
      end
    end
  end
end
