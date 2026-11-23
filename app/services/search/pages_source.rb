# frozen_string_literal: true

module Search
  class PagesSource < BaseSource
    protected

    def group_key   = :pages
    def group_label = I18n.t("chrome.inline_search.groups.pages")

    def items
      pattern = "%#{escaped_like.downcase}%"
      Page.where(customer_id: customer.id).or(Page.shared)
          .where("LOWER(name) LIKE ? ESCAPE '\\'", pattern)
          .order(:name)
          .limit(MAX_PER_GROUP)
          .map { |p|
            {
              label: p.name,
              path:  "/#{customer.id}/admin/maintenance/pages/#{p.id}",
              type:  :page
            }
          }
    end
  end
end
