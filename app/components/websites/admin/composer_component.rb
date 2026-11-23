# frozen_string_literal: true

module Websites
  module Admin
    # Two-pane page composer: identity + sortable kit sections on the left,
    # admin preview iframe on the right. Stimulus host: website-builder.
    class ComposerComponent < ApplicationComponent
      FORM_ID = "website-page-form"
      LAYOUT_FORM_ID = "website-layout-form"
      TEMPLATE_ID = SectionEditorComponent::PLACEHOLDER_ID

      attr_reader :page, :form_url, :preview_url, :http_method, :presentation

      def initialize(page:, form_url: nil, preview_url: nil, method: :patch,
                     identity_only: false, structure_locked: true, layouts: [],
                     kind: :page, embedded: false, sections_only: false,
                     json_name: nil, form_id: nil, upload_url: nil, public_path: nil, presentation: nil)
        @page = page
        @form_url = form_url
        @preview_url = preview_url
        @public_path = public_path
        @http_method = method
        @identity_only = identity_only
        @structure_locked = structure_locked
        @layouts = Array(layouts)
        @kind = kind.to_sym
        @embedded = embedded
        @sections_only = sections_only
        @json_name = json_name
        @form_id = form_id
        @upload_url = upload_url
        if !layout_kind? && presentation.instance_of?(Websites::HomeSite::Presentation) && presentation.matches_page?(page)
          @presentation = presentation
        end
      end

      def form_id
        @form_id.presence || (layout_kind? ? LAYOUT_FORM_ID : FORM_ID)
      end

      def form_scope
        layout_kind? ? :website_layout : :website_page
      end

      def json_name
        @json_name.presence || "#{form_scope}[sections_json]"
      end

      def sections
        Array(page_attr(:sections)).map { |section| normalize_section(section) }
      end

      def page_title
        layout_kind? ? page_attr(:name).to_s : page_attr(:title).to_s
      end

      def layout_key_value
        page_attr(:key).to_s
      end

      def layout_description_value
        page_attr(:description).to_s
      end

      def persisted_record?
        page.respond_to?(:persisted?) && page.persisted?
      end

      def home?
        flag?(:home)
      end

      def nav_visible?
        value = flag?(:nav_visible)
        return true if value.nil?

        value
      end

      def published?
        flag?(:published) || false
      end

      def sections_json
        sections.to_json
      end

      def preview?
        preview_url.present?
      end

      def preview_address
        @public_path.presence || t("website.admin.pages.edit.preview_address")
      end

      def identity_only?
        @identity_only
      end

      def structure_locked?
        @structure_locked
      end

      def layout_kind?
        @kind == :layout
      end

      def embedded?
        @embedded
      end

      def sections_only?
        @sections_only
      end

      def show_identity?
        !sections_only?
      end

      def show_sections?
        !identity_only?
      end

      def show_preview?
        show_sections? && !embedded? && !layout_kind?
      end

      def workspace?
        show_preview?
      end

      def collapse_identity?
        workspace? && persisted_record?
      end

      def preview_viewports
        %w[desktop tablet mobile]
      end

      def builder_actions
        actions = [ "turbo:submit-end->website-builder#reloadPreview" ]
        actions << "submit->website-builder#persist" if workspace?
        actions << "keydown@window->website-builder#saveShortcut"
        actions.join(" ")
      end

      def layouts
        @layouts
      end

      def selected_layout_key
        page_attr(:layout_key).presence || inferred_layout_key.to_s
      end

      def inferred_layout_key
        Websites::Catalog.infer_layout_key(sections)
      end

      def upload_url
        @upload_url.to_s
      end

      def image_upload?
        upload_url.present?
      end

      def layout_name
        layout = page.try(:layout)
        return layout.display_name if layout
        return if selected_layout_key.blank?

        I18n.exists?("website.layouts.#{selected_layout_key}.name") ? I18n.t("website.layouts.#{selected_layout_key}.name") : selected_layout_key
      end

      def errors_message
        errors = page.try(:errors)
        return if errors.blank? || !errors.respond_to?(:full_messages) || errors.none?

        errors.full_messages.join(" · ").presence
      end

      def kit_types
        Websites::SectionKit::TYPES
      end

      def theme_key_value
        return page.theme_key.to_s if page.respond_to?(:theme_key)

        page.is_a?(Hash) ? (page[:theme_key] || page["theme_key"]).to_s : ""
      end

      # Page: site theme, (new pages) the layout's pairing, or a named theme.
      # Layout: its code pairing, or a named theme override.
      def theme_options
        presets = Websites::ThemePresets.keys.map { |key| [Websites::ThemePresets.name(key), key] }
        if layout_kind?
          paired = Websites::ThemePairing.for_layout(layout_key_value)
          [[I18n.t("website.admin.pages.form.theme_paired", name: Websites::ThemePresets.name(paired)), ""], *presets]
        else
          inherited = [[I18n.t("website.admin.pages.form.theme_site"), ""]]
          inherited << [I18n.t("website.admin.pages.form.theme_layout"), Websites::Activities::SavePage::LAYOUT_THEME] if identity_only?
          [*inherited, *presets]
        end
      end

      # The theme the page renders with, so Design swatches show real colors.
      def site_theme
        @site_theme ||= if layout_kind? && page.respond_to?(:theme_preset_key)
          Websites::Theme.for_record(page)
        elsif (website = page.try(:website))
          Websites::Theme.for_page(website: website, page: page)
        else
          Websites::Theme.new
        end
      end

      def empty_defaults_for(type)
        props = Websites::SectionKit::STRING_PROPS.fetch(type, []).index_with { "" }
        array_key = Websites::SectionKit::ARRAY_PROPS[type]
        if array_key
          min = type == "proof_strip" ? 4 : 0
          props[array_key] = Array.new(min) { {} }
        end
        props["tone"] = "light" if type == "hero_cinematic"
        props["image_side"] = "left" if type == "split_image_text"
        props
      end

      def template_section(type)
        {
          "id" => TEMPLATE_ID,
          "type" => type,
          "props" => empty_defaults_for(type)
        }
      end

      def site_pages
        website = page.try(:website)
        return [] unless website.respond_to?(:pages)

        website.pages.filter_map do |item|
          slug = item.try(:home?) ? "" : item.try(:slug).to_s
          next if slug.blank?

          { "title" => item.try(:title).to_s, "slug" => slug }
        end
      end

      def defaults_for(section, index)
        templates = Array(page.try(:layout)&.sections).map { |raw| raw.respond_to?(:stringify_keys) ? raw.stringify_keys : {} }
        match = templates.find { |item| item["id"].to_s == section["id"].to_s }
        match ||= templates[index] if templates[index].is_a?(Hash) && templates[index]["type"] == section["type"]
        raw = match ? match["props"] : nil
        props = raw.presence || section["props"].presence || empty_defaults_for(section["type"].to_s)
        props.respond_to?(:stringify_keys) ? props.stringify_keys : {}
      end

      def shell_class
        workspace? ? "flex min-h-0 flex-1 flex-col xl:flex-row" : "max-w-4xl"
      end

      def form_class
        workspace? ? "flex h-full min-h-0 flex-col" : "flex flex-col gap-6"
      end

      def editor_pane_class
        if workspace?
          "flex min-h-0 min-w-0 flex-1 flex-col bg-surface xl:h-full xl:w-[28rem] xl:max-w-[38%] xl:flex-none xl:border-r xl:border-border-subtle"
        else
          "flex min-w-0 flex-col gap-5"
        end
      end

      def preview_pane_class
        if workspace?
          "flex h-full min-h-0 min-w-0 flex-1 flex-col bg-canvas max-xl:hidden xl:min-w-[24rem]"
        else
          "flex min-w-0 flex-col gap-3 xl:sticky xl:top-4"
        end
      end

      def pane_btn_class
        "rounded-md px-3 py-1.5 text-sm font-medium text-text-secondary transition-colors hover:text-text-primary aria-pressed:bg-surface aria-pressed:font-semibold aria-pressed:text-text-primary aria-pressed:shadow-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
      end

      def viewport_btn_class
        "inline-flex size-8 items-center justify-center rounded-md text-text-tertiary transition-colors hover:bg-surface hover:text-text-primary aria-pressed:bg-surface aria-pressed:text-text-primary aria-pressed:shadow-xs aria-pressed:ring-1 aria-pressed:ring-border-subtle"
      end

      private

      def page_attr(name)
        if page.respond_to?(name)
          page.public_send(name)
        elsif page.respond_to?(:[])
          page[name] || page[name.to_s]
        end
      end

      def flag?(name)
        predicate = "#{name}?"
        raw = page.respond_to?(predicate) ? page.public_send(predicate) : page_attr(name)
        return if raw.nil?

        ActiveModel::Type::Boolean.new.cast(raw)
      end

      def normalize_section(section)
        hash = section.respond_to?(:to_h) ? section.to_h : section
        hash = hash.stringify_keys if hash.respond_to?(:stringify_keys)
        props = hash["props"] || hash[:props] || {}
        props = props.stringify_keys if props.respond_to?(:stringify_keys)
        {
          "id" => hash["id"] || hash[:id],
          "type" => hash["type"] || hash[:type],
          "props" => props
        }
      end
    end
  end
end
