# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Authentication
        # Presentation metadata only. Never feed these names back into grant keys.
        # Resolve both locales explicitly so I18n fallbacks cannot leak English
        # controller humanizations into the Chinese permissions catalog.
        class GrantRouteLabel
          MODULE_ALIASES = { "payments" => "payment", "emails" => "email", "assistant" => "ai_assistant" }.freeze
          NAVIGATION_KEYS = {
            "assistants" => "ai_assistant", "members" => "member_portal",
            "sign_up" => "member_registration", "forget_password" => "password_reset",
            "roles" => "roles_permissions", "user_role_assignments" => "user_access",
            "template_tokens" => "email_personalization", "merchant_accounts" => "payment_providers"
          }.freeze
          RESOURCE_KEYS = {
            "settings" => "common.actions.settings", "credentials" => "captcha.platform_settings.credentials_section",
            "entities" => "settings_people.areas.entities", "pages" => "settings_people.areas.pages",
            "page_shortcuts" => "page_shortcuts.title",
            "docs" => "chrome.help_menu.docs.label",
            "module_howtos" => "admin_modules.index.howto.title",
            "modules" => "chrome.menu_bar.items.modules", "maintenances" => "settings_people.areas.maintenance",
            "role_grants" => "settings_people.permissions", "invoices" => "settings_navigation.items.invoices",
            "payment_methods" => "settings_navigation.items.billing_payment_methods",
            "subscriptions" => "maint_platform.billing.breadcrumbs.subscriptions",
            "plan_changes" => "settings_billing.subscription.cancel_change",
            "invoice_payments" => "comp_billing.invoice_detail.pay_invoice",
            "plans" => "maint_platform.billing.breadcrumbs.plans", "coupons" => "maint_platform.billing.breadcrumbs.coupons",
            "search" => "common.actions.search", "constants" => "admin_misc.maintenance.cards.constants_title",
            "customer_profiles" => "admin_misc.maintenance.cards.customer_profile_title",
            "entity_pages" => "settings_people.sources.entities.name",
            "messages" => "admin_modules.nav.messages", "attachments" => "chrome.help_menu.email.attachments",
            "templates" => "admin_modules.nav.templates", "refunds" => "feature_modules.payment.member.refunds",
            "layouts" => "website.platform.layouts.heading", "media" => "website.admin.pages.form.groups.media",
            "countable_items" => "comp_billing.countable_items_form.heading",
            "code_generators" => "chrome.sidebar.maintenance.code_generators",
            "previews" => "common.labels.preview", "website" => "settings_navigation.items.website",
            "sites" => "settings_navigation.items.website",
            "member_sources" => "settings_people.grant_resources.page_groups",
            "member_surfaces" => "settings_people.display_settings"
          }.freeze
          SCOPES = %w[platform maintenance settings].freeze

          def initialize(subject_key)
            @parts = subject_key.to_s.split("/")
          end

          def label
            join([context, resource_label(parts.last) || I18n.t("settings_people.grant_resources.other")])
          end

          def context
            scope = SCOPES.find { |part| parts.include?(part) } || (parts.include?("modules") ? "module_records" : "admin")
            # Retain meaningful intermediate areas (e.g. Email, SMS, Billing,
            # website pages) while discarding routing scaffolding.
            areas = parts[1...-1].to_a.reject { |part| (SCOPES + ["modules"]).include?(part) }
            join([I18n.t("settings_people.areas.#{scope}"), *areas.filter_map { |part| module_label(part) || resource_label(part) }])
          end

          def resource_label(resource)
            mod = parts.filter_map { |part| module_key(part) }.last
            keys = [
              (AccessPoints::SmsRouteLabels.key_for(parts.join("/")) if resource == parts.last),
              NAVIGATION_KEYS[resource] && "settings_navigation.items.#{NAVIGATION_KEYS[resource]}",
              RESOURCE_KEYS[resource],
              "settings_people.grant_resources.#{resource}"
            ]
            if mod
              keys.concat(%w[entries tabs titles settings].map { |area| "feature_modules.#{mod}.#{area}.#{resource}" })
            end
            # Existing area locale files consistently expose list headings and
            # breadcrumbs. Reuse those instead of maintaining a route-by-route map.
            roots = ["maint_platform.#{resource}", "maint_core.#{resource}", "admin_misc.#{resource}",
                     "admin_modules.#{mod}.#{resource}", "#{mod}.#{resource}"]
            keys.concat(roots.flat_map { |root| %w[index.title title breadcrumb].map { |suffix| "#{root}.#{suffix}" } })
            keys << "common.labels.#{resource}"
            translate_first(keys.compact)
          end

          private

          attr_reader :parts

          def join(labels)
            labels.compact.uniq.reduce { |context, resource| I18n.t("settings_people.grant_label", context: context, resource: resource) }
          end

          def module_key(part)
            key = MODULE_ALIASES.fetch(part, part)
            key if translated_key?("feature_modules.#{key}.name")
          end

          def module_label(part)
            key = module_key(part)
            return I18n.t("feature_modules.#{key}.name") if key

            translate_first(["settings_people.grant_contexts.#{part}"])
          end

          def translate_first(keys)
            key = keys.find { |candidate| translated_key?(candidate) }
            I18n.t(key) if key
          end

          def translated_key?(key)
            %i[en zh-CN].all? do |locale|
              value = I18n.t(key, locale: locale, fallback: false, default: nil)
              value.is_a?(String) && !value.include?("%{") && !value.include?("<")
            end
          end
        end
      end
    end
  end
end
