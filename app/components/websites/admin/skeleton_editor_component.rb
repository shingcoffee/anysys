# frozen_string_literal: true

module Websites
  module Admin
    # Owner editor for a multi-page skeleton: identity plus nested page drafts.
    class SkeletonEditorComponent < ApplicationComponent
      FORM_ID = "website-skeleton-form"

      PageDraft = Struct.new(:title, :slug, :home, :nav_visible, :published, :sections, :layout_key, keyword_init: true) do
        def home? = !!home
        def nav_visible? = nav_visible.nil? ? true : nav_visible
        def published? = !!published
      end

      def initialize(skeleton:, layouts:, form_url:, customer_id:)
        @skeleton = skeleton
        @layouts = Array(layouts)
        @form_url = form_url
        @customer_id = customer_id
      end

      attr_reader :skeleton, :layouts, :form_url, :customer_id

      def form_id
        FORM_ID
      end

      def pages
        skeleton.page_list
      end

      def draft_for(page)
        hash = page.stringify_keys
        PageDraft.new(
          title: hash["title"],
          slug: hash["slug"],
          home: hash["home"],
          nav_visible: hash["nav_visible"],
          published: false,
          sections: Array(hash["sections"]),
          layout_key: hash["layout_key"]
        )
      end

      def layout_options
        layouts.map { |layout| [layout.display_name, layout.key] }
      end

      def theme_options
        paired = Websites::ThemePairing.for_skeleton(skeleton.key)
        presets = Websites::ThemePresets.keys.map { |key| [Websites::ThemePresets.name(key), key] }
        [[t("website.admin.pages.form.theme_paired", name: Websites::ThemePresets.name(paired)), ""], *presets]
      end

      def category
        Websites::Skeletons.category_for(skeleton.key)
      end

      def category_label
        I18n.t("website.skeletons.categories.#{category}")
      end

      def inspired_by_credit
        brand_key = "website.skeletons.#{skeleton.key}.inspired_by"
        format_key = "website.skeletons.inspired_by_format"
        return unless I18n.exists?(brand_key) && I18n.exists?(format_key)

        I18n.t(format_key, brand: I18n.t(brand_key))
      end
    end
  end
end
