# frozen_string_literal: true

module Admin
  module Entities
    # The entity browse surface around a tab body: the entity header with its
    # Create Entry action (plus any tab-specific `actions`), then Entries /
    # Pages tabs with their counts. A nil `form_count` (bridge entities, whose
    # pages are unbound) leaves only Entries, so no tabs show.
    class BrowseComponent < ApplicationComponent
      include EntityAttributeGroupingHelper

      TABS = %i[entries pages].freeze
      ENTRIES_ICON = "M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 010 3.75H5.625a1.875 1.875 0 010-3.75z"

      attr_reader :entity, :customer_id, :tab

      def initialize(entity:, customer_id:, entry_count:, form_count:, tab: :entries, actions: [])
        @entity = entity
        @customer_id = customer_id
        @entry_count = entry_count
        @form_count = form_count
        @tab = TABS.include?(tab) ? tab : TABS.first
        @extra_actions = Array(actions)
      end

      def creatable? = entity.active? && !entity.category_bridge?

      def actions
        create = { label: t("admin_misc.entities.entry_form.create"),
                   path: helpers.new_admin_entity_entry_path(customer_id, entity),
                   variant: :primary, icon: :plus, class: "min-h-11 w-full sm:w-auto", data: { turbo_frame: "_top" } }
        [(create if creatable?), *@extra_actions].compact
      end

      def label = entity.display_label.to_s

      def breadcrumbs
        [{ label: t("admin_misc.domains.breadcrumb"), path: helpers.admin_domains_path(customer_id) }, { label: label }]
      end

      def description = t("admin_misc.entities.show.description", name: label.downcase)
      def icon_path = attribute_group_icon_path(entity.icon)
      def icon_class = "#{attribute_group_color_classes(entity.color.presence || 'slate', variant: :bar)} text-white"

      def tabs
        entries = { id: :entries, label: t("admin_misc.domains.directory.columns.entries"), count: @entry_count,
                    icon_path: ENTRIES_ICON, path: helpers.admin_entity_path(customer_id, entity),
                    active: tab == :entries }
        return [entries] if @form_count.nil?

        [entries, { id: :pages, label: t("admin_misc.domains.tabs.pages"), count: @form_count,
                    icon_path: Admin::Pages::OpsTableComponent::FORM_ICON,
                    path: helpers.admin_entity_pages_path(customer_id, entity), active: tab == :pages }]
      end
    end
  end
end
