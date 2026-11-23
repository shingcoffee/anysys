# frozen_string_literal: true

module CustomerDocs
  # The repository supplies the complete localized directory and resolved paths.
  class HomeGuidesComponent < ApplicationComponent
    # Customer topics mirror the top menu, so they reuse its icons.
    GROUP_ICONS = {
      "home" => MenuIconComponent::PATHS[:home],
      "assistant" => MenuIconComponent::PATHS[:assistant],
      "users" => MenuIconComponent::PATHS[:users],
      "payments" => MenuIconComponent::PATHS[:payments],
      "communication" => MenuIconComponent::PATHS[:communication],
      "entities" => MenuIconComponent::PATHS[:entities],
      "content" => MenuIconComponent::PATHS[:pages],
      "settings" => MenuIconComponent::PATHS[:settings],
      "orientation" => "M9 4.5 3 7v12.5l6-2.5 6 2.5 6-2.5V4.5L15 7 9 4.5Zm0 0V17m6-10v12.5",
      "access" => "M12 3 4.5 6v5.25c0 4.4 3.2 8.5 7.5 9.75 4.3-1.25 7.5-5.35 7.5-9.75V6L12 3Zm-3 9 2 2 4-4",
      "builders" => "M14.7 6.3a4 4 0 0 0-5.3 5.3L3.5 17.5a1.77 1.77 0 0 0 2.5 2.5l5.9-5.9a4 4 0 0 0 5.3-5.3l-2.4 2.4-2.1-.4-.4-2.1 2.4-2.4Z",
      "runtime" => "M13 3 4.5 13.5H11L10 21l8.5-10.5H12L13 3Z",
      "modules" => MenuIconComponent::PATHS[:modules],
      "operations" => MenuIconComponent::PATHS[:maintenance]
    }.freeze
    DEFAULT_GROUP_ICON = MenuIconComponent::PATHS[:pages]

    attr_reader :groups, :translation_scope

    def initialize(groups:, translation_scope: "customer_docs")
      @groups = groups
      @translation_scope = translation_scope
    end

    def heading_id
      reference? ? "developer-doc-guides-title" : "customer-doc-guides-title"
    end

    def guide_title_id(guide)
      "#{guide_id_prefix}-#{guide.slug}-title"
    end

    def guide_summary_id(guide)
      "#{guide_id_prefix}-#{guide.slug}-summary"
    end

    def group_panel_id(group)
      "#{guide_id_prefix}-group-#{group.key}"
    end

    def group_description(group)
      t("#{translation_scope}.group_descriptions.#{group.key}")
    end

    def group_icon_path(group)
      GROUP_ICONS.fetch(group.key.to_s, DEFAULT_GROUP_ICON)
    end

    def reference?
      translation_scope == "developer_docs"
    end

    private

    def guide_id_prefix
      reference? ? "developer-doc-guide" : "customer-doc-guide"
    end
  end
end
