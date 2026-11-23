# frozen_string_literal: true

module Websites
  module Admin
    # Settings / Website body. The sticky jump nav is a website-theme-picker
    # scrollspy; theme tokens must stay radios so the form posts them.
    class SettingsFormComponent < ApplicationComponent
      FORM_ID = "website-settings-form"
      MAX_COLUMNS = 4
      MAX_LINKS = 8
      WEBSITE_ICON_PATH = ::Admin::Maintenance::Platform::ModuleSettingsHelper::MODULE_ICON_PATHS.fetch("website")

      THEME_GROUPS = [
        { token: "appearance", values: Websites::Theme::APPEARANCES, grid: "grid max-w-md grid-cols-2 gap-3" },
        { token: "accent", values: Websites::Theme::ACCENTS, grid: "flex flex-wrap gap-x-2 gap-y-3" },
        { token: "type", values: Websites::Theme::TYPES, grid: "grid grid-cols-2 gap-3 sm:grid-cols-3 @3xl/theme:grid-cols-4" },
        { token: "density", values: Websites::Theme::DENSITIES, grid: "grid max-w-md grid-cols-2 gap-3" },
        { token: "corners", values: Websites::Theme::CORNERS, grid: "grid max-w-lg grid-cols-3 gap-3" },
        { token: "neutral", values: Websites::Theme::NEUTRALS, grid: "grid max-w-lg grid-cols-3 gap-3" }
      ].freeze
      PRESET_CARD_CLASS = [
        "flex h-full flex-col overflow-hidden rounded-xl border border-border-subtle bg-surface text-left shadow-xs transition",
        "hover:border-border peer-checked:border-accent peer-checked:ring-2 peer-checked:ring-accent",
        "peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-accent"
      ].join(" ")

      NAV_ACTIVE_CLASS = "bg-accent-subtle font-medium text-accent-text"
      NAV_INACTIVE_CLASS = "font-normal text-text-secondary hover:bg-surface-hover hover:text-text-primary"
      NAV_LINK_CLASS = "flex min-h-10 shrink-0 items-center whitespace-nowrap rounded-md px-3 py-2 text-sm leading-snug transition-colors focus-visible:outline-2 focus-visible:outline-accent xl:min-h-9 xl:whitespace-normal"
      SWITCH_CLASS = "relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent bg-border transition-colors duration-200 ease-in-out after:absolute after:left-0 after:top-0 after:size-5 after:rounded-full after:bg-surface after:shadow after:transition-transform after:duration-200 after:ease-in-out peer-checked:bg-success peer-checked:after:translate-x-5 peer-focus-visible:ring-2 peer-focus-visible:ring-accent peer-focus-visible:ring-offset-2"

      def initialize(website:, customer_id: nil, form_url: nil, layouts: nil)
        @website = website
        @customer_id = customer_id
        @form_url = form_url
        @layouts = layouts
      end

      attr_reader :website

      def form_id
        FORM_ID
      end

      def missing_site?
        website.blank?
      end

      def form_url
        return @form_url if @form_url.present?

        helpers.admin_settings_modules_website_site_path(resolved_customer_id)
      end

      def resolved_customer_id
        @customer_id.presence || website.try(:customer_id)
      end

      def theme
        @theme ||= Websites::Theme.new(hash_for(website.try(:theme)))
      end

      def seo_hash
        hash_for(website.try(:seo))
      end

      def footer_hash
        hash_for(website.try(:footer))
      end

      def footer_columns
        Array(footer_hash["columns"]).map { |column| hash_for(column) }.first(MAX_COLUMNS)
      end

      def add_column_slot?
        footer_columns.size < MAX_COLUMNS
      end

      def links_for(column)
        links = Array(column["links"]).map { |link| hash_for(link) }.first(MAX_LINKS)
        links << {} if links.size < MAX_LINKS
        links
      end

      def published?
        ActiveModel::Type::Boolean.new.cast(website.try(:published))
      end

      def layouts
        @layouts.nil? ? Websites::Catalog.layouts : Array(@layouts)
      end

      def selected_layout_key
        website.try(:default_layout_key).to_s.presence || layouts.first&.key.to_s
      end

      def layout_groups
        Websites::LayoutFamily.group(layouts, first: website.try(:skeleton_key)).map do |family, items|
          [Websites::LayoutFamily.label(family), items]
        end
      end

      def site_address
        return if resolved_customer_id.blank?

        helpers.page_shortcuts_mounted_path(PageShortcuts::PublicPath.website_home(customer_id: resolved_customer_id, host: helpers.request.host))
      end

      def status_tile_class
        published? ? "bg-success-subtle text-success" : "bg-surface-hover text-text-tertiary"
      end

      def field_error(attribute)
        return unless website.respond_to?(:errors) && website.errors

        website.errors.full_messages_for(attribute).first
      end

      def errors_message
        return unless website.respond_to?(:errors) && website.errors&.any?

        website.errors.full_messages.join(" · ").presence || I18n.t("website.admin.flash.site_save_failed")
      end

      def presets
        Websites::ThemePresets.keys.map do |key|
          { key: key, theme: Websites::ThemePresets.theme(key), tokens: Websites::ThemePresets.tokens(key),
            name: Websites::ThemePresets.name(key), description: Websites::ThemePresets.description(key) }
        end
      end

      def preset_checked?(key)
        theme.preset_key == key
      end

      def customized?(key)
        preset_checked?(key) && theme.customized?
      end

      # Every pairing's families, so preset cards and type specimens render true.
      def font_library_url
        Websites::Fonts.stylesheet_url(Websites::Fonts.keys)
      end

      def theme_picker_tokens
        appearances = Websites::Theme::APPEARANCES.index_with do |appearance|
          theme_for = Websites::Theme.new("appearance" => appearance)
          {
            "page" => theme_for.dark? ? "bg-neutral-950 text-white" : "bg-white text-neutral-950",
            "muted" => theme_for.muted_text_class,
            "accents" => Websites::Theme::ACCENTS.index_with { |accent|
              pair = Websites::Theme.new("appearance" => appearance, "accent" => accent)
              { "kicker" => pair.kicker_class, "button" => pair.filled_button_class }
            }
          }
        end

        types = Websites::Theme::TYPES.index_with do |type|
          typed = Websites::Theme.new("type" => type)
          {
            "headline" => typed.type_headline_class,
            "body" => typed.type_body_class,
            "style" => "--font-site-heading: #{typed.heading_stack}; --font-site-body: #{typed.body_stack};"
          }
        end

        densities = {
          "spacious" => { "pad" => "gap-3 p-5 sm:p-6" },
          "compact" => { "pad" => "gap-2 p-4 sm:p-5" }
        }

        corners = Websites::Theme::CORNERS.index_with do |corner|
          shaped = Websites::Theme.new("corners" => corner)
          { "style" => css_vars(Websites::Theme::RADII.fetch(corner)), "button" => shaped.button_shape_class }
        end

        neutrals = Websites::Theme::NEUTRALS.index_with do |neutral|
          ramp = Websites::Theme::NEUTRAL_RAMPS.fetch(neutral).transform_keys { |shade| "--color-neutral-#{shade}" }
          { "style" => css_vars(ramp) }
        end

        appearances.merge("types" => types, "densities" => densities, "corners" => corners, "neutrals" => neutrals)
      end

      def nav_link_class
        "#{NAV_LINK_CLASS} #{NAV_INACTIVE_CLASS}"
      end

      def jump_items
        items = [
          { href: "#website-settings-publish-heading", label: t("website_settings.publishing.heading") },
          { href: "#website-settings-identity-heading", label: t("website.admin.settings.identity.heading") },
          { href: "#website-settings-theme-heading", label: t("website.admin.settings.theme.appearance") },
          { href: "#website-settings-seo-heading", label: t("website_settings.search.heading") },
          { href: "#website-settings-footer-heading", label: t("website.admin.settings.footer.heading") }
        ]
        items << { href: "#website-settings-layout-heading", label: t("website_settings.page_defaults") } if layouts.any?
        items << { href: "#website-settings-skeleton-heading", label: t("website_settings.starter.heading") } if content?
        items
      end

      private

      def css_vars(vars)
        vars.map { |name, value| "#{name}: #{value};" }.join(" ")
      end

      def hash_for(value)
        return {} if value.blank?
        return value.to_unsafe_h.stringify_keys if value.respond_to?(:to_unsafe_h)
        return value.stringify_keys if value.respond_to?(:stringify_keys)
        return value.to_h.stringify_keys if value.respond_to?(:to_h)

        {}
      end
    end
  end
end
