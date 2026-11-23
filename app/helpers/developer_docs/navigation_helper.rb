# frozen_string_literal: true

module DeveloperDocs
  module NavigationHelper
    def docs_navigation_label(slug, title:, translation_scope:)
      return title unless translation_scope == "customer_docs"

      I18n.t("#{translation_scope}.nav_labels.#{slug}", default: title)
    end
  end
end
