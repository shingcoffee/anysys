# frozen_string_literal: true

module Admin
  module Domains
    # A domain's page: the header naming the domain (tinted with its colour)
    # over a row of stat cards for its totals — record types, entries, pages
    # and last activity — then any body. A customer without domains keeps the generic
    # Domains header, its one section being everything; with nothing to
    # browse, an empty state replaces the totals. The sidebar lists each
    # domain's record types. Entity CUD stays on the assistant and the
    # platform-owner maintenance surface — this page never offers it.
    class BrowseComponent < ApplicationComponent
      Stat = Data.define(:key, :label, :value, :time) do
        def numeric? = key != :activity
      end

      STAT_ICONS = {
        record_types: EntitiesContributor::ICONS[:all],
        entries: "M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125",
        pages: "M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z",
        activity: "M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
      }.freeze

      attr_reader :section, :customer_id

      # `sections` is every section of the directory; `section` the one shown
      # (nil when there is nothing to browse).
      def initialize(sections:, section:, customer_id:)
        @sections = Array(sections)
        @section = section
        @customer_id = customer_id
      end

      # Whether the header names the section: only once the customer has domains.
      def named? = section.present? && @sections.any? { |candidate| !candidate.ungrouped? }

      def breadcrumbs
        root = { label: t("admin_misc.domains.breadcrumb") }
        return [root] unless named?

        [root.merge(path: helpers.admin_domains_path(customer_id)), { label: title }]
      end

      def title
        return t("admin_misc.domains.title") unless named?

        section.ungrouped? ? t("chrome.sidebar.entities.ungrouped") : section.domain.name
      end

      def description
        return t("admin_misc.domains.description") unless named?
        return t("admin_misc.domains.directory.ungrouped_hint") if section.ungrouped?

        section.domain.description.presence || t("admin_misc.domains.description")
      end

      def icon_path
        return unless named?

        EntitiesContributor::ICONS[section.ungrouped? ? :ungrouped : :domain]
      end

      def icon_class
        return "bg-surface-active text-text-tertiary" if section.ungrouped?

        "#{EntityDomainColors.tile(section.domain.color)} ring-1 ring-inset"
      end

      def stats
        return [] unless section

        [
          Stat.new(key: :record_types, label: t("chrome.sidebar.entities.record_types"),
                   value: number(section.record_type_count), time: nil),
          Stat.new(key: :entries, label: t("admin_misc.domains.directory.stats.entries"),
                   value: number(section.entry_count), time: nil),
          Stat.new(key: :pages, label: t("admin_misc.domains.tabs.pages"), value: number(section.form_count), time: nil),
          Stat.new(key: :activity, label: t("admin_misc.domains.directory.stats.last_activity"),
                   value: last_activity, time: section.last_entry_at)
        ]
      end

      def stat_value_classes(stat)
        return "text-3xl font-semibold leading-9 tabular-nums tracking-tight text-text-primary" if stat.numeric?

        "min-w-0 pb-1 text-base font-semibold #{stat.time ? "text-text-primary" : "text-text-muted"}"
      end

      private

      def number(value) = helpers.number_with_delimiter(value)

      def last_activity
        return t("admin_misc.domains.directory.stats.no_activity") if section.last_entry_at.nil?

        t("chrome.admin_table.time_ago", time: helpers.time_ago_in_words(section.last_entry_at))
      end
    end
  end
end
