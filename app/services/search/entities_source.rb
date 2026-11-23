# frozen_string_literal: true

module Search
  class EntitiesSource < BaseSource
    protected

    def group_key   = :entities
    def group_label = I18n.t("chrome.inline_search.groups.entities")

    def items
      pattern = "%#{escaped_like.downcase}%"
      Entity.where(customer_id: customer.id).or(Entity.shared)
            .where("LOWER(display_label) LIKE ? ESCAPE '\\'", pattern)
            .order(:display_label)
            .limit(MAX_PER_GROUP)
            .map { |e| { label: e.display_label, path: "/#{customer.id}/admin/entities/#{e.id}", type: :entity } }
    end
  end
end
