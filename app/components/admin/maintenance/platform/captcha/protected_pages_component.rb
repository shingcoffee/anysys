# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module Captcha
        # Two stacked sections: captcha-protected URLs vs skipped URLs.
        # `surfaces` and `pages` are arrays of hashes from the module-settings
        # controller; each identity appears in exactly one section.
        class ProtectedPagesComponent < ApplicationComponent
          GROUP_ORDER = %w[authentication account mfa payments email oauth other shared_pages].freeze

          def initialize(surfaces:, toggle_url:, pages: [])
            @surfaces = Array(surfaces)
            @toggle_url = toggle_url
            @pages = Array(pages)
          end

          attr_reader :toggle_url

          def empty? = items.empty?

          def protected_groups = grouped(protected_items)
          def skip_groups = grouped(skip_items)
          def protected_count = protected_items.size
          def skip_count = skip_items.size
          def protected_empty? = protected_items.empty?
          def skip_empty? = skip_items.empty?

          def sections
            [
              {
                id: "protected",
                heading_id: "captcha-protected-heading",
                title: I18n.t("maint_platform.module_settings.show.captcha.pages_title"),
                subtitle: I18n.t("maint_platform.module_settings.show.captcha.pages_subtitle"),
                search_id: "captcha-protected-search",
                search_label: I18n.t("maint_platform.module_settings.show.captcha.protected_search"),
                empty_copy: I18n.t("maint_platform.module_settings.show.captcha.protected_empty"),
                count: protected_count,
                empty: protected_empty?,
                groups: protected_groups,
                badge_variant: :primary
              },
              {
                id: "skip",
                heading_id: "captcha-skip-heading",
                title: I18n.t("maint_platform.module_settings.show.captcha.skip_title"),
                subtitle: I18n.t("maint_platform.module_settings.show.captcha.skip_subtitle"),
                search_id: "captcha-skip-search",
                search_label: I18n.t("maint_platform.module_settings.show.captcha.skip_search"),
                empty_copy: I18n.t("maint_platform.module_settings.show.captcha.skip_empty"),
                count: skip_count,
                empty: skip_empty?,
                groups: skip_groups,
                badge_variant: :default
              }
            ]
          end

          def surface_toggle_aria(item)
            I18n.t("captcha.throttle.aria", name: item[:name])
          end

          GROUP_ICONS = {
            "authentication" => "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
            "account" => "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
            "mfa" => "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
            "payments" => "M3 10h18M7 15h1m4 0h1m-7 4h12a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
            "email" => "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
            "oauth" => "M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z",
            "other" => "M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z",
            "shared_pages" => "M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
          }.freeze

          def group_icon_path(key)
            GROUP_ICONS.fetch(key.to_s, GROUP_ICONS.fetch("other"))
          end

          private

          def items
            @items ||= display_surfaces + display_pages
          end

          def protected_items
            items.reject { |item| item[:skipped] }
          end

          def skip_items
            items.select { |item| item[:skipped] }
          end

          def grouped(list)
            buckets = GROUP_ORDER.index_with { [] }
            list.each do |item|
              key = infer_group(item)
              buckets[key] << item
            end
            GROUP_ORDER.filter_map do |key|
              next if buckets[key].blank?

              { key: key, label: I18n.t("captcha.surface_groups.#{key}"), items: buckets[key] }
            end
          end

          def display_surfaces
            @surfaces.map do |surface|
              {
                key: surface[:key].to_s,
                group: surface[:group].to_s,
                name: surface_name(surface),
                path: surface[:path].to_s,
                skipped: surface[:skipped] == true,
                fail_closed: surface[:fail_closed] == true,
                launched: nil,
                url: toggle_url,
                extra_params: { surface_key: surface[:key] },
                preset: surface[:preset] || Captcha::ThrottlePresets::PRESET_100_PER_5MIN,
                limit_count: surface[:limit_count],
                period_minutes: surface[:period_minutes]
              }
            end
          end

          def display_pages
            @pages.map do |page|
              {
                key: "page-#{page[:id]}",
                group: "shared_pages",
                name: page[:name].to_s,
                path: page[:public_path].to_s,
                skipped: page[:skipped] == true,
                fail_closed: false,
                launched: page[:launched],
                url: page[:update_url],
                extra_params: {},
                preset: page[:preset] || Captcha::ThrottlePresets::PRESET_100_PER_5MIN,
                limit_count: page[:limit_count],
                period_minutes: page[:period_minutes]
              }
            end
          end

          def surface_name(surface)
            explicit = surface[:name]
            return explicit if explicit.present?

            i18n_key = "captcha.surfaces.#{surface[:key].to_s.tr('/#', '_')}"
            I18n.exists?(i18n_key) ? I18n.t(i18n_key) : I18n.t("captcha.surfaces.discovered", key: surface[:key])
          end

          def infer_group(item)
            explicit = item[:group].to_s
            return explicit if GROUP_ORDER.include?(explicit)

            case item[:key].to_s
            when %r{\Aauthentication/registrations#account} then "account"
            when %r{\Aauthentication/mfa} then "mfa"
            when %r{\Aauthentication/} then "authentication"
            when %r{\Apayments/} then "payments"
            when %r{\Aemails/} then "email"
            when %r{\Aoauth/} then "oauth"
            when /\Apage-/ then "shared_pages"
            else "other"
            end
          end
        end
      end
    end
  end
end
