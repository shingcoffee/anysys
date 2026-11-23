# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      module ModuleSettings
        # The three panes owned by ModuleSettingsController: Overview (what the
        # module is and whether customers get it), Configuration (platform
        # defaults), and Developer (models, template tokens, handoff contract).
        # Provider / resource / operations surfaces are nested routes with their
        # own controllers, not branches in here.
        class ShowComponent < ApplicationComponent
          def initialize(feature_module:, module_models:, customer_id:,
                         customer_signup_enabled: nil, selected_model: nil, pane: :overview)
            @feature_module = feature_module
            @module_models = Array(module_models)
            @customer_id = customer_id
            @customer_signup_enabled = customer_signup_enabled
            @selected_model_name = selected_model
            @pane = pane.to_sym
          end

          attr_reader :feature_module, :module_models, :customer_id,
                      :customer_signup_enabled, :pane

          def developer? = pane == :developer
          def configuration? = pane == :configuration
          def overview? = !developer? && !configuration?

          def schema
            feature_module.configuration_schema_json || {}
          end

          def authentication?
            feature_module.key.to_s == "authentication"
          end

          # PATCH target for the toggles in this pane. `section` is the pane to
          # return to after the redirect, so a toggle never bounces the operator
          # back to Overview from Developer. `model` is only sent for a
          # non-default selection so the redirect lands on the URL already open.
          def setting_path
            helpers.admin_maintenance_platform_module_setting_path(
              customer_id, feature_module, **{ section: pane, model: model_query_value }.compact
            )
          end

          def selected_model
            return @selected_model if defined?(@selected_model)

            @selected_model = module_models.find { |model| model[:name] == @selected_model_name } || module_models.first
          end

          def selected_model?(model) = model[:name] == selected_model&.fetch(:name)

          def model_path(model)
            helpers.developer_admin_maintenance_platform_module_setting_path(
              customer_id, feature_module, **{ model: (model[:name] unless model.equal?(module_models.first)) }.compact
            )
          end

          def model_query_value
            return nil unless developer? && selected_model && !selected_model.equal?(module_models.first)

            selected_model[:name]
          end

          def model_link_classes(model)
            base = "relative flex min-w-[10rem] shrink-0 items-center justify-between gap-3 rounded-md px-3 py-2 transition-colors " \
                   "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent lg:min-w-0 lg:shrink"
            state = selected_model?(model) ? "bg-surface-active text-text-primary" : "text-text-secondary hover:bg-surface-hover hover:text-text-primary"
            "#{base} #{state}"
          end

          def model_columns(model) = Array(model[:columns])

          def model_meta(model)
            [
              I18n.t("maint_platform.module_settings.show.models.column_count", count: model[:columns_count].to_i),
              I18n.t("maint_platform.module_settings.show.models.association_count", count: model[:associations_count].to_i)
            ].join(" · ")
          end

          def attribute_search_text(column)
            [column[:name], column[:label], column[:type]].compact.join(" ")
          end

          def platform_token_keys
            @platform_token_keys ||= ::Emails::TemplateToken.platform.pluck(:source_key).to_set
          end

          def token_source_key(model_name, column_name)
            "#{model_name.underscore.tr('/', '_')}.#{column_name}"
          end

          # Overview identity facts. Kept out of the page header so the header
          # stays the same shape as every other admin page. A fact with nothing
          # behind it (an unversioned module) is omitted rather than shown as a
          # dash.
          def detail_items
            [
              { label: I18n.t("maint_platform.module_settings.show.module_key"), value: feature_module.key, mono: true },
              (feature_module.version.presence && { label: I18n.t("maint_platform.module_settings.show.version"), value: feature_module.version }),
              { label: I18n.t("maint_platform.module_settings.show.summary.configuration"), value: configuration_label },
              { label: I18n.t("maint_platform.module_settings.show.models.title"), value: module_models.size.to_s }
            ].compact
          end

          def configuration_label
            return I18n.t("maint_platform.module_settings.show.summary.configuration_available") if authentication? || schema.any?

            I18n.t("maint_platform.module_settings.show.summary.configuration_none")
          end

          def required_disabled_reason
            return I18n.t("maint_platform.module_settings.show.locked_hint") if feature_module.mandatory?
            return I18n.t("maint_platform.module_settings.show.required_disabled_hint") unless feature_module.active?

            nil
          end

          def handoff_disabled_reason
            return nil if feature_module.active?

            I18n.t("maint_platform.module_settings.show.handoff_disabled_hint")
          end

          def version_label
            feature_module.version.presence || I18n.t("maint_platform.module_settings.show.summary.unavailable")
          end

          def extendable_attribute_count(model)
            Array(model[:columns]).count { |column| feature_module.extendable_attribute_allowed?(model[:name], column[:name]) }
          end

          def extendable_attribute_field_id(model_name, attribute)
            "extendable_attribute_#{model_name.to_s.parameterize(separator: "_")}_#{attribute.to_s.parameterize(separator: "_")}"
          end

          def schema_field_id(key)
            "config_defaults_#{key.to_s.parameterize(separator: "_")}"
          end

          def schema_field_label(key, definition)
            i18n_key = "admin_misc.module_config.fields.#{feature_module.key}.#{key}"
            return I18n.t(i18n_key) if I18n.exists?(i18n_key)

            definition["label"].presence || key.to_s
          end

          def schema_option_pairs(key, definition)
            Array(definition["options"]).map do |opt|
              i18n_key = "admin_misc.module_config.options.#{feature_module.key}.#{key}.#{opt}"
              label = I18n.exists?(i18n_key) ? I18n.t(i18n_key) : opt.to_s
              [label, opt]
            end
          end
        end
      end
    end
  end
end
