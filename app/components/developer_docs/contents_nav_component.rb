# frozen_string_literal: true

module DeveloperDocs
  # Grouped contents list shared by the desktop rail and the mobile drawer.
  # Every group is a labelled section, so any page is one click away.
  class ContentsNavComponent < ApplicationComponent
    include DeveloperDocs::NavigationHelper

    attr_reader :page, :translation_scope, :navigate, :surface

    def initialize(page:, translation_scope:, navigate: false, surface: :desktop)
      @page = page
      @translation_scope = translation_scope
      @navigate = navigate
      @surface = surface
    end

    def reader_text(key)
      t("#{translation_scope}.#{key}")
    end

    # Customer rows show a short task label; the full title becomes their description.
    def customer?
      translation_scope == "customer_docs"
    end

    def searching?
      page.query.present?
    end

    def current_entry?(entry)
      entry.active && !searching?
    end

    def navigation_label(entry)
      docs_navigation_label(entry.slug, title: entry.title, translation_scope: translation_scope)
    end

    def title_id(entry)
      "#{translation_scope.delete_suffix('_docs')}-doc-nav-#{surface}-#{entry.slug}-title"
    end

    def group_heading_id(group)
      "#{translation_scope.delete_suffix('_docs')}-doc-nav-#{surface}-group-#{group.key}"
    end

    def nav_link_class(active)
      base = "relative flex min-w-0 flex-col items-start justify-center gap-1 rounded-md px-2.5 py-1.5 text-sm [overflow-wrap:anywhere] transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-inset #{target_height_class}"
      if active
        "#{base} bg-accent-subtle font-medium text-accent-text before:absolute before:-left-2 before:top-1.5 before:bottom-1.5 before:w-0.5 before:rounded-full before:bg-accent"
      else
        "#{base} text-text-secondary hover:bg-surface-active hover:text-text-primary"
      end
    end

    def link_data(active = false)
      data = navigate ? { action: "click->developer-docs-nav#navigate" } : {}
      data[:docs_current_guide] = true if active
      data
    end

    private

    def target_height_class
      surface.to_sym == :mobile ? "min-h-11" : "min-h-8"
    end
  end
end
