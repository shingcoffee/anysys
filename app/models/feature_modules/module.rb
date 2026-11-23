# frozen_string_literal: true

module FeatureModules
  class Module < ApplicationRecord
    self.table_name = "feature_modules"

    include JsonSerializable

    json_attribute :configuration_schema, default: {}
    json_attribute :extendable_models, default: []
    json_attribute :extendable_attributes, default: {}

    enum :status, { active: 0, inactive: 1 }, default: :inactive

    has_many :customer_feature_modules, dependent: :destroy,
                                        class_name: "FeatureModules::CustomerAssignment",
                                        foreign_key: :feature_module_id
    has_many :customers, through: :customer_feature_modules
    has_many :feature_module_logs, dependent: :destroy,
                                   class_name: "FeatureModules::Log",
                                   foreign_key: :feature_module_id

    validates :key, presence: true, uniqueness: true
    validates :name, presence: true
    # Required implies active: a module cannot be required for all customers
    # while it is platform-inactive. Enforces the invariant at the data layer,
    # not just in the controller guard.
    validates :required, exclusion: { in: [true], message: ->(*) { I18n.t("maint_platform.errors.validations.required_needs_active_module") } },
                         if: :inactive?
    # Handoff-target implies active: an inactive module can never be a live
    # handoff target (Invocation.begin! gates on handoff_enabled?, so pinning
    # the invariant at the data layer makes the runtime check transitively
    # guarantee active — not just the controller's clear-on-deactivate).
    validates :handoff_enabled, exclusion: { in: [true], message: ->(*) { I18n.t("maint_platform.errors.validations.handoff_needs_active_module") } },
                                if: :inactive?

    scope :available, -> { where(status: :active) }
    scope :by_name, -> { order(:name) }
    scope :required, -> { where(required: true) }
    # Modules the platform owner has opted into being a handoff *target* — the
    # only modules a resource (Page, etc.) may hand control off to.
    scope :handoff_enabled, -> { where(handoff_enabled: true) }
    scope :enabled_for_customer, ->(customer_id) {
      return none if customer_id.blank?

      where(status: :active)
        .joins(:customer_feature_modules)
        .where(customer_feature_modules: { customer_id: customer_id, status: :active })
    }
    scope :available_for_customer, ->(customer_id) {
      return required.available if customer_id.blank?

      enabled_ids = enabled_for_customer(customer_id).select(:id)
      where(id: enabled_ids).or(required.available).distinct
    }

    def self.enabled?(key:, customer_id:)
      return false if customer_id.blank?

      enabled_for_customer(customer_id).exists?(key: key)
    end

    # Route params address a module by key (see #to_param); accept a row id too
    # so a hand-typed or historical numeric URL still resolves.
    def self.find_by_param!(param)
      param.to_s.match?(/\A\d+\z/) ? find(param) : find_by!(key: param)
    end

    # User-facing module name, localized per request. Falls back to the
    # stored English +name+ when a module has no translation key yet.
    def display_name
      I18n.t("feature_modules.#{key}.name", default: name)
    end

    # The key is the module's URL vocabulary everywhere else — the nested
    # platform surfaces live at /module_settings/<key>/… — so route helpers
    # address a module by key too rather than by an opaque row id. Lookups
    # still accept either (see ModuleSettingsController#find_feature_module).
    def to_param
      key
    end

    def mandatory?
      registration_class.respond_to?(:mandatory?) && registration_class.mandatory?
    end

    def extendable_model?(class_name)
      extendable_models_json.include?(class_name.to_s)
    end

    def extendable_attributes_configured?(class_name)
      extendable_attributes_json.is_a?(Hash) && extendable_attributes_json.key?(class_name.to_s)
    end

    def extendable_attributes_for(class_name)
      Array(extendable_attributes_json[class_name.to_s]).map(&:to_s)
    end

    # Nothing is allowed until the owner checks it. A saved list, including an
    # empty one, is that selection.
    def extendable_attribute_allowed?(class_name, attribute)
      return false unless extendable_model?(class_name)

      extendable_attributes_for(class_name).include?(attribute.to_s)
    end

    def set_extendable_model!(class_name, on)
      name = class_name.to_s
      set = Array(extendable_models_json).dup
      attributes = extendable_attribute_hash
      if on
        set |= [name]
      else
        set -= [name]
        attributes.delete(name)
      end
      update!(extendable_models: set.to_json, extendable_attributes: attributes.to_json)
    end

    # `candidates` is the attribute names this model may offer. The selection
    # starts empty, so checking one attribute allows only that attribute.
    def set_extendable_attribute!(class_name, attribute, on, candidates:)
      name = class_name.to_s
      attribute = attribute.to_s
      return unless extendable_model?(name)

      known = Array(candidates).map(&:to_s)
      return unless known.include?(attribute)

      current = extendable_attributes_for(name)
      current = on ? (current | [attribute]) : (current - [attribute])
      update!(extendable_attributes: extendable_attribute_hash.merge(name => current).to_json)
    end

    def extendable_attribute_hash
      hash = extendable_attributes_json
      hash.is_a?(Hash) ? hash.deep_dup : {}
    end

    def registration_class
      "FeatureModules::#{key.camelize}::Registration".constantize
    rescue NameError
      NullRegistration
    end

    module NullRegistration
      def self.provision!(_customer) = nil
      def self.deprovision!(_customer) = nil
      def self.entry_path_for(_customer) = nil
      def self.default_exit_config = nil
      def self.sidebar_contributions(_ctrl) = { entries: [], settings: [] }
      def self.entries_for(entry_key:, params:) = raise NotImplementedError
      def self.before_request(_controller) = nil

      def self.input_contract_class
        @input_contract_class ||= ::Class.new(Reform::Form)
      end

      def self.input_contract_properties = []
      def self.input_contract_fields = []
      def self.output_contract_fields = []

      def self.output_contract_class
        @output_contract_class ||= ::Class.new(Reform::Form)
      end
    end
  end
end
