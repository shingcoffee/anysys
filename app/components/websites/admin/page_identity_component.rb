# frozen_string_literal: true

module Websites
  module Admin
    # Title and page preferences for the page/layout composer. On a new page
    # (identity_only) it renders bare fields; NewPageComponent supplies the card.
    # In the workspace it is a drill-in panel opened from the sections outline.
    class PageIdentityComponent < ApplicationComponent
      def initialize(composer:, form:)
        @composer = composer
        @form = form
      end

      attr_reader :form

      delegate :workspace?, :layout_name,
               :layout_kind?, :identity_only?, :persisted_record?, :home?,
               :nav_visible?, :published?,
               :page_title, :layout_key_value, :layout_description_value,
               :theme_key_value, :theme_options, to: :@composer

      def preference_fields
        identity_only? ? %i[nav_visible published] : %i[nav_visible published home]
      end

      def preference_hint(field)
        case field
        when :published then "website.admin.pages.form.published_hint"
        when :home then "website.admin.pages.form.home_locked" if home?
        end
      end

      def theme_field(compact:)
        tag.div(class: "flex flex-col gap-1.5") do
          safe_join([
            form.label(:theme_key, t("website.admin.pages.form.theme"), class: "form-label mb-0"),
            form.select(:theme_key, options_for_select(theme_options, theme_key_value), {},
                        class: "input-field #{compact ? 'h-9' : 'h-10'}",
                        aria: { describedby: form.field_id(:theme_key, :hint) },
                        data: { action: "change->website-builder#markDirty" }),
            tag.p(t(layout_kind? ? "website.platform.layouts.form.theme_hint" : "website.admin.pages.form.theme_hint"),
                  id: form.field_id(:theme_key, :hint), class: "text-sm text-text-tertiary")
          ])
        end
      end

      def drill_in?
        workspace? && persisted_record?
      end

      def collapse_identity?
        false
      end

      def wrapper_tag
        identity_only? ? :div : :section
      end

      def wrapper_options
        return { class: "min-w-0", data: { page_identity: true } } if identity_only?

        {
          class: drill_in? ? "group/identity min-w-0 hidden" : (workspace? ? "group/identity min-w-0" : "card overflow-hidden"),
          data: { identity_panel: true },
          aria: { labelledby: "website-page-identity-heading" }
        }.compact
      end

      def show_header?
        !identity_only? && !drill_in?
      end

      def chrome_btn_class
        "inline-flex size-8 items-center justify-center rounded-md text-text-tertiary transition-colors hover:bg-surface-hover hover:text-text-primary focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent pointer-coarse:size-10"
      end

      def body_class
        spacing = if identity_only?
          ""
        elsif drill_in?
          "px-0.5 pt-1 pb-2"
        elsif workspace?
          "px-0.5 pt-1 pb-4"
        else
          "px-4 py-4 sm:px-5"
        end
        ["flex flex-col gap-4", spacing].compact_blank.join(" ")
      end
    end
  end
end
