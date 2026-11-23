# frozen_string_literal: true

module Websites
  module Activities
    class ReorderPages
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)

      def self.call(website:, ordered_ids:)
        requested = Array(ordered_ids).map(&:to_i)
        owned = website.pages.where(id: requested).pluck(:id)
        ordered = requested.select { |id| owned.include?(id) }
        rest = website.pages.where.not(id: ordered).order(:position).pluck(:id)

        WebsitePage.transaction do
          (ordered + rest).each_with_index do |id, index|
            website.pages.where(id: id).update_all(position: index, updated_at: Time.current)
          end
        end

        Result.new(success?: true, model: website.reload, errors: [])
      end
    end
  end
end
