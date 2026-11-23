# frozen_string_literal: true

# FeatureModules::BaseModule
#
# Abstract base class for all feature module registrations.
# Subclasses must implement module_key, module_name, and provision!.
#
module FeatureModules
  class BaseModule
    # DSL collector used inside input_contract / output_contract blocks.
    class ContractDsl
      attr_reader :properties

      def initialize
        @properties = []
      end

      # `type:` is an OPTIONAL first-class declaration of the field's logical
      # type (:integer, :number, :boolean, :enum, :string, :datetime, :hash…).
      # It drives the mapping-UI badge and the runtime InputCaster. When omitted,
      # HandoffField infers the type from the validators (back-compatible).
      # `source:` declares WHO may supply this input at runtime:
      #   :author_only   (default) — must be author-mapped; never user-entered.
      #   :user_fillable — the end user may complete/override it on the module's
      #                    entry page (see FeatureModules::HandoffCompletion).
      # Defaulting to :author_only is fail-safe: a forgotten annotation keeps the
      # strict "must be mapped" behavior rather than silently exposing a field.
      def property(name, type: nil, source: nil, validates: nil, **_ignored)
        @properties << { name: name.to_s, type: type&.to_s,
                         source: (source || :author_only).to_s, validates: validates || {} }
      end
    end

    class << self
      def module_key
        raise NotImplementedError, "#{name} must implement .module_key"
      end

      def module_name
        raise NotImplementedError, "#{name} must implement .module_name"
      end

      def module_description
        ""
      end

      def configuration_schema
        {}
      end

      # Per-customer settings shown in Settings but edited only by the platform
      # owner from the customer's Maintenance / Modules page.
      def owner_managed_configuration_keys
        []
      end

      def provision!(customer)
        raise NotImplementedError, "#{name} must implement .provision!"
      end

      def deprovision!(customer)
        # Optional cleanup — default no-op
      end

      def enabled_for?(customer_id)
        FeatureModules::Module.enabled?(key: module_key, customer_id: customer_id)
      end

      # Generic per-request hook. Called by FeatureModules::HostIntegration concern
      # for every module enabled for the current customer, on every request.
      # Override in subclasses to enforce access control, set context, etc.
      # Must not raise — redirect via the controller and return.
      def before_request(controller)
        nil
      end

      # Dashboard sidebar contribution hook. Called by ModulesContributor
      # and SettingsContributor. Return a hash with :entries and :settings
      # (arrays of ModuleContribution).
      def sidebar_contributions(_controller)
        { entries: [], settings: [] }
      end

      # Resolve the collection backing a module entry. Called by the
      # Admin::ModuleEntriesController when rendering a module entry page.
      def entries_for(entry_key:, params:)
        raise NotImplementedError,
              "#{name} must implement .entries_for(entry_key:, params:) to use module entries"
      end

      # Mark this module permanently active + required for every customer.
      # Mandatory modules are not owner-toggleable (e.g. User Authentication).
      def mandatory!
        @mandatory = true
      end

      def mandatory?
        @mandatory == true
      end

      # Register or update the FeatureModules::Module record WITHOUT clobbering
      # owner-managed status/required on existing rows.
      def register!
        fm = ::FeatureModules::Module.find_or_initialize_by(key: module_key)
        fm.name                  = module_name
        fm.description           = module_description
        persisted_schema = fm.configuration_schema_json
        fm.configuration_schema = configuration_schema.to_h.transform_keys(&:to_s).to_h do |key, field|
          definition = field.stringify_keys
          configured = persisted_schema.is_a?(Hash) ? persisted_schema[key] : nil
          definition["default"] = configured["default"] if configured.is_a?(Hash) && configured.key?("default")
          [key, definition]
        end.to_json

        if mandatory?
          fm.status   = :active
          fm.required = true
        elsif fm.new_record?
          fm.status   = :inactive
          fm.required = false
        end
        # else: preserve persisted owner-set status/required.

        fm.save!
      end

      # ---- Handoff DSL ----

      # entry_path { |customer| "/#{customer.id}/demo/start" }
      def entry_path(&block)
        @entry_path_block = block
      end

      def entry_path_for(customer)
        @entry_path_block&.call(customer)
      end

      # I18n scope of the framework entry step that collects user_fillable
      # inputs (FeatureModules::HandoffEntryComponent): `fields.<name>.label`
      # per field, optional `title` / `subtitle` / `continue` overrides.
      #   handoff_entry_i18n "comp_payments.handoff_entry"
      def handoff_entry_i18n(scope)
        @handoff_entry_i18n_scope = scope.to_s
      end

      def handoff_entry_i18n_scope
        @handoff_entry_i18n_scope || "feature_modules.#{module_key}.handoff_entry"
      end

      # default_exit kind: "route", name: "customer_home"
      def default_exit(**config)
        validate_default_exit!(config)
        @default_exit_config = config
      end

      def default_exit_config
        @default_exit_config
      end

      def input_contract(&block)
        definitions = collect_contract_properties(&block)
        @input_contract_fields = definitions.map { |defn| HandoffField.from(defn) }
        @input_contract_class  = build_contract_class(definitions)
      end

      def input_contract_class
        @input_contract_class ||= empty_contract_class
      end

      # Ordered rich descriptors of the input-contract fields (name, required,
      # type, allowed values, constraint). The single source of truth for both
      # the platform "Integration Contract" card and the page-builder mapping UI.
      def input_contract_fields
        @input_contract_fields ||= []
      end

      # Ordered list of input-contract property names (strings), derived from the
      # fields. Kept because the page-builder mapping UI keys its rows on names.
      def input_contract_properties
        input_contract_fields.map(&:name)
      end

      def output_contract(&block)
        definitions = collect_contract_properties(&block)
        @output_contract_fields = definitions.map { |defn| HandoffField.from(defn) }
        @output_contract_class  = build_contract_class(definitions)
      end

      def output_contract_class
        @output_contract_class ||= empty_contract_class
      end

      # Ordered rich descriptors of the output-contract fields — the values a
      # module returns to the page on completion.
      def output_contract_fields
        @output_contract_fields ||= []
      end

      private

      def validate_default_exit!(config)
        kind = config[:kind].to_s
        unless %w[page flowchart url route].include?(kind)
          raise FeatureModules::RegistrationError,
                "#{name}.default_exit has unknown kind: #{kind.inspect}"
        end
      end

      def collect_contract_properties(&block)
        dsl = ContractDsl.new
        dsl.instance_eval(&block) if block
        dsl.properties
      end

      def build_contract_class(definitions)
        Class.new(Reform::Form) do
          definitions.each do |defn|
            property defn[:name]
            validates defn[:name], **defn[:validates] if defn[:validates].present?
          end
        end
      end

      def empty_contract_class
        Class.new(Reform::Form)
      end
    end
  end
end
