# frozen_string_literal: true

module Admin
  class ModuleConfigsController < ApplicationController
    dashboard_menu_item :settings
    before_action :load_feature_module

    def show
      @entry_key = params[:entry_key]
      @default_exit = @feature_module.registration_class.default_exit_config
      @exit_override = parse_exit_override(@customer_feature_module) if @feature_module.handoff_enabled?
    end

    def update
      # Merge onto the existing blob — never replace it. A module's
      # `configuration` JSON can hold keys written by OTHER surfaces (e.g. the
      # Authentication module's `allow_registration` / `allow_password_reset`
      # toggles have their own dedicated controllers). Replacing the whole blob
      # with only this page's whitelisted keys silently wiped those, resetting
      # them to their defaults.
      @customer_feature_module.merge_configuration!(configuration_params)

      redirect_to admin_module_config_path(current_customer_id, @feature_module.key.pluralize),
                  notice: t("common.flash.configuration_updated")
    rescue ArgumentError => e
      redirect_to admin_module_config_path(current_customer_id, @feature_module.key.pluralize),
                  alert: e.message
    rescue StandardError => e
      Rails.logger.warn("[module_configs.update] #{e.class}: #{e.message}")
      redirect_to admin_module_config_path(current_customer_id, @feature_module.key.pluralize),
                  alert: t("common.flash.configuration_update_failed")
    end

    private

    def load_feature_module
      key = resolve_module_key(params[:key])
      @feature_module = FeatureModules::Module.find_by!(key: key)
      return head :not_found unless FeatureModules::Module.enabled?(
        key: @feature_module.key, customer_id: current_customer.id
      )
      @customer_feature_module = FeatureModules::CustomerAssignment.find_by!(
        customer_id: current_customer.id, feature_module_id: @feature_module.id
      )
    end

    # URL segment is the plural module path (e.g. "payments"); the registry
    # key may be singular (e.g. "payment"). Prefer the URL segment, fall back
    # to its singular form.
    def resolve_module_key(segment)
      return segment if FeatureModules::Module.exists?(key: segment)

      singular = segment.to_s.singularize
      FeatureModules::Module.exists?(key: singular) ? singular : segment
    end

    # Only persist a known set of configuration keys for the module. The
    # whitelist is keyed off the module's `registration_class` when it
    # declares one; otherwise we fall back to the small fixed set the
    # views currently expose. Without this gate, an admin could write
    # arbitrary keys into `CustomerAssignment.configuration` JSON and
    # alter business logic that reads that hash.
    DEFAULT_CONFIG_KEYS = %i[exit_landing_page entry_landing_page enabled].freeze

    def configuration_params
      raw = params[:configuration]
      return {} if raw.blank?
      unless raw.is_a?(ActionController::Parameters)
        raise ArgumentError, I18n.t("common.flash.configuration_must_be_object")
      end

      allowed = if @feature_module&.registration_class&.respond_to?(:configuration_keys)
                  @feature_module.registration_class.configuration_keys
      else
                  DEFAULT_CONFIG_KEYS
      end

      # Only handoff-enabled modules expose an exit URL. Never accept a crafted
      # override for a module that the platform owner has disabled for handoff.
      owner_managed = Array(@feature_module.registration_class.try(:owner_managed_configuration_keys)).map(&:to_sym)
      scalars = Array(allowed).map(&:to_sym) - %i[exit_landing_page entry_landing_page] - owner_managed
      nested = { entry_landing_page: %i[kind url name page_id] }
      nested[:exit_landing_page] = %i[kind url name page_id] if @feature_module.handoff_enabled?
      raw.permit(*scalars, nested).to_h
    end

    def parse_exit_override(cfm)
      return nil unless cfm
      parsed = cfm.configuration.is_a?(String) ? JSON.parse(cfm.configuration) : cfm.configuration
      parsed && parsed["exit_landing_page"]
    rescue JSON::ParserError
      nil
    end
  end
end
