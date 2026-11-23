# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  # Platform-owner module settings. The three panes this controller renders
  # (Overview / Configuration / Developer) are separate GET actions with their
  # own paths rather than `?tab=` state, so every section tab in the workspace
  # nav is a plain, bookmarkable link — the same IA as the nested per-module
  # surfaces (`/module_settings/email/credentials`, `/module_settings/sms/templates`, …).
  class ModuleSettingsController < ApplicationController
    dashboard_menu_item :maintenance

    # Panes rendered by this controller, in nav order. Anything else (Providers,
    # Resources, Operations) is a nested per-module route.
    PANES = %i[overview configuration developer].freeze

    def index
      @available_modules = FeatureModules::Module.by_name
    end

    def show
      @pane = :overview
      load_module_workspace
      render :show
    end

    def configuration
      @pane = :configuration
      load_module_workspace
      render :show
    end

    def developer
      @pane = :developer
      @selected_model = selected_model_param
      load_module_workspace
      render :show
    end

    def update
      @feature_module = find_feature_module

      # The platform owner may edit ANY module's settings here — being "required
      # for all customers" only locks the customer-side disable toggle, not the
      # platform owner's ability to configure the module. The only structurally
      # fixed knobs are a mandatory module's status/required toggles (the module
      # Registration forces them back on every boot via `register!`), so those
      # two mutations are no-ops for mandatory modules; every other setting
      # (config defaults, extendable models, module-specific config) is editable.
      normalize_checkbox_flags!
      ActiveRecord::Base.transaction do
        @feature_module.lock!
        validate_update_request!
        apply_status!          if params.key?(:status_active)
        apply_required!        if params.key?(:required)
        apply_handoff_enabled! if params.key?(:handoff_enabled)
        apply_extendable_model! if params.key?(:extendable) && params.key?(:extendable_model)
        apply_extendable_attribute! if params.key?(:extendable_attribute)
        apply_config_defaults! if params.key?(:config_defaults)
        apply_token_attribute! if params[:token_model].present? && params[:token_attribute].present?
        apply_customer_signup! if @feature_module.key == "authentication" && params.key?(:allow_customer_signup)
      end

      respond_to do |format|
        format.html { redirect_to pane_path, notice: t("maint_platform.flash.module_settings.updated", name: @feature_module.display_name) }
        format.json { render json: { success: true, enabled: params[:token_enabled] == "1" } }
      end
    rescue ActiveRecord::RecordNotFound
      raise
    rescue StandardError => e
      Rails.logger.warn("[module_settings.update] #{e.class}: #{e.message}")
      respond_to do |format|
        format.html { redirect_to pane_path, alert: t("maint_platform.flash.module_settings.update_failed") }
        format.json { render json: { success: false, error: t("maint_platform.flash.module_settings.update_failed") }, status: :unprocessable_entity }
      end
    end

    private

    def normalize_checkbox_flags!
      %i[extendable_attribute_enabled].each do |key|
        params[key] = params[key].last if params[key].is_a?(Array)
      end
    end

    def validate_update_request!
      %i[status_active required handoff_enabled extendable extendable_attribute_enabled token_enabled allow_customer_signup].each do |key|
        next unless params.key?(key)

        raise ArgumentError unless params[key].is_a?(String) && %w[0 1].include?(params[key])
      end

      if params.key?(:config_defaults)
        raise ArgumentError unless params[:config_defaults].is_a?(ActionController::Parameters)

        schema = @feature_module.configuration_schema_json || {}
        params[:config_defaults].slice(*schema.keys).each do |key, value|
          raise ArgumentError unless valid_default_value?(schema.fetch(key), value)
        end
      end

      if params.key?(:extendable_model) || params.key?(:extendable) || params.key?(:extendable_attribute)
        class_name = params[:extendable_model]
        raise ArgumentError unless class_name.is_a?(String)
        raise ArgumentError unless ModuleModelDiscovery.call(@feature_module.key).any? { |model| model[:name] == class_name }
      end

      if params.key?(:extendable_attribute)
        attribute = params[:extendable_attribute]
        raise ArgumentError unless attribute.is_a?(String) && attribute.match?(/\A[a-z][a-z0-9_]*\z/)
      end

      if params.key?(:token_model) || params.key?(:token_attribute) || params.key?(:token_enabled)
        model_name, attribute = params.values_at(:token_model, :token_attribute)
        raise ArgumentError unless model_name.is_a?(String) && model_name.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/) &&
                                   attribute.is_a?(String) && attribute.match?(/\A[a-z_]\w*\z/) && params.key?(:token_enabled)
        if params[:token_enabled] == "1" && Authentication::User::SENSITIVE_COLUMNS.include?(attribute)
          raise ArgumentError, t("maint_platform.flash.module_settings.token_attribute_forbidden")
        end
      end
    end

    def valid_default_value?(definition, value)
      case definition["type"]
      when "boolean"
        [true, false, "0", "1", "true", "false"].include?(value)
      when "integer"
        (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.match?(/\A-?\d+\z/)
      when "number"
        (value.is_a?(String) || value.is_a?(Numeric)) && Float(value, exception: false)&.finite?
      when "select"
        value.is_a?(String) && Array(definition["options"]).include?(value)
      else
        value.is_a?(String)
      end
    end

    def load_module_workspace
      @feature_module = find_feature_module
      @module_models  = ModuleModelDiscovery.call(@feature_module.key)
      @customer_signup_enabled = ::Authentication::PlatformSettings.customer_signup_enabled? if @feature_module.key == "authentication"
    end

    def find_feature_module
      FeatureModules::Module.find_by_param!(params[:id])
    end

    def apply_status!
      return if @feature_module.mandatory? # mandatory modules are always active

      active = params[:status_active] == "1"
      turning_off = !active && @feature_module.active?
      attrs  = { status: active ? :active : :inactive }
      unless active
        attrs[:required]        = false # required implies active
        attrs[:handoff_enabled] = false # a platform-inactive module can't be a live handoff target
      end
      ActiveRecord::Base.transaction do
        @feature_module.update!(attrs)
        # Match tenant disable: drop live vendor credentials/accounts so cron
        # and other non-HTTP paths cannot keep charging after a platform off.
        deprovision_all_customers! if turning_off
      end
    end

    def deprovision_all_customers!
      Customer.find_each do |customer|
        @feature_module.registration_class.deprovision!(customer)
      end
    end

    def apply_handoff_enabled!
      return unless @feature_module.active? # only an active module can be a handoff target

      @feature_module.update!(handoff_enabled: params[:handoff_enabled] == "1")
    end

    def apply_required!
      return if @feature_module.mandatory? # mandatory modules are always required
      return unless @feature_module.active? # required requires active

      new_required = params[:required] == "1"
      @feature_module.update!(required: new_required)
      provision_required_for_all! if new_required
    end

    def provision_required_for_all!
      Customer.find_each do |customer|
        cfm = FeatureModules::CustomerAssignment.find_or_initialize_by(customer: customer, feature_module: @feature_module)
        next if cfm.persisted? && cfm.active?

        @feature_module.registration_class.provision!(customer)
        cfm.update!(status: :active, enabled_at: Time.current, configuration: cfm.configuration.presence || {}.to_json)
      end
    end

    def apply_extendable_model!
      class_name = params[:extendable_model].to_s
      known = ModuleModelDiscovery.call(@feature_module.key).any? { |m| m[:name] == class_name }
      return unless known

      @feature_module.set_extendable_model!(class_name, params[:extendable] == "1")
    end

    def apply_extendable_attribute!
      class_name = params[:extendable_model].to_s
      attribute = params[:extendable_attribute].to_s
      model = ModuleModelDiscovery.call(@feature_module.key).find { |discovered| discovered[:name] == class_name }
      return unless model && @feature_module.extendable_model?(class_name)

      candidates = Array(model[:columns]).filter_map { |column| column[:name].to_s.presence }
      @feature_module.set_extendable_attribute!(
        class_name, attribute, params[:extendable_attribute_enabled] == "1", candidates: candidates
      )
    end

    def apply_config_defaults!
      schema = @feature_module.configuration_schema_json || {}
      return if schema.empty?

      raw = params[:config_defaults]
      return unless raw.is_a?(ActionController::Parameters)

      permitted = raw.permit(*schema.keys).to_h
      merged = schema.each_with_object({}) do |(key, defn), acc|
        acc[key] = defn.merge("default" => permitted.fetch(key, defn["default"]))
      end
      @feature_module.update!(configuration_schema: merged.to_json)
    end

    def apply_customer_signup!
      ::Authentication::PlatformSettings.instance.update!(
        allow_customer_signup: params[:allow_customer_signup] == "1"
      )
    end

    def apply_token_attribute!
      model_name = params[:token_model].to_s
      attr_name  = params[:token_attribute].to_s
      enabled    = params[:token_enabled] == "1"

      source_key = "#{model_name.underscore.tr('/', '_')}.#{attr_name}"
      label      = "#{model_name.demodulize}.#{attr_name}"

      if Authentication::User::SENSITIVE_COLUMNS.include?(attr_name)
        raise ArgumentError, I18n.t("maint_platform.flash.module_settings.token_attribute_forbidden") if enabled

        ::Emails::TemplateToken.platform.where(source_key: source_key).destroy_all
        return
      end

      if enabled
        ::Emails::TemplateToken.find_or_create_by!(
          source_type: ::Emails::TemplateToken::SOURCE_PLATFORM,
          source_key: source_key
        ) do |token|
          token.customer_id = nil
          token.label       = label
        end
      else
        ::Emails::TemplateToken.platform.where(source_key: source_key).destroy_all
      end
    end

    # Developer-pane model selection. Only a class-name shape is passed through;
    # the component falls back to the first model for anything not discovered.
    def selected_model_param
      value = params[:model]
      value if value.is_a?(String) && value.match?(/\A[A-Z]\w*(?:::[A-Z]\w*)*\z/)
    end

    # Where a mutation returns to. `section` is an opaque pane name, never a
    # URL, so a crafted value can only ever fall back to Overview.
    def pane_path
      case params[:section].to_s
      when "configuration"
        configuration_admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module)
      when "developer"
        developer_admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module,
                                                                 model: selected_model_param)
      else
        admin_maintenance_platform_module_setting_path(current_customer_id, @feature_module)
      end
    end
  end
end
end
end
