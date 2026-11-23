# frozen_string_literal: true

# DynamicClassLoader
#
# Dynamically builds model and contract classes into a namespace module using
# Ruby metaprogramming. Classes are constructed at runtime from the entity's
# property_schema - no stored code strings or module_eval required.
#
# For entity-bound flowcharts, builds typed EntityEntry subclasses with
# attribute accessors derived from property_schema.
#
# For blueprint flowcharts (nil entity), creates BlueprintEntity/BlueprintEntityContract
# placeholder classes with stub implementations.
#
# @example Loading entity classes into a namespace
#   loader = DynamicClassLoader.new(entity)
#   namespace = Module.new
#   loader.load_into(namespace)
#   # Now namespace::UserProfile and namespace::UserProfileContract are available
#
# @example Loading blueprint classes for flowcharts without bound entity
#   loader = DynamicClassLoader.new(nil)
#   namespace = Module.new
#   loader.load_into(namespace)
#   # Now namespace::BlueprintEntity and namespace::BlueprintEntityContract are available
#
class DynamicClassLoader
  include Loggable

  BLUEPRINT_MODEL_NAME = "BlueprintEntity"
  BLUEPRINT_CONTRACT_NAME = "BlueprintEntityContract"

  attr_reader :entity

  def initialize(entity)
    @entity = entity
  end

  # Load model and contract classes into the given namespace module
  # @param namespace [Module] the module to load classes into
  # @return [Hash] containing :model_class and :contract_class names
  def load_into(namespace)
    if entity.present?
      build_entity_model(namespace)
      build_entity_contract(namespace)
    else
      build_blueprint_model(namespace)
      build_blueprint_contract(namespace)
    end

    {
      model_class: model_class_name,
      contract_class: contract_class_name
    }
  end

  # Get the model class name that will be/was loaded
  def model_class_name
    @model_class_name ||= entity_slug&.camelize || BLUEPRINT_MODEL_NAME
  end

  # Get the contract class name that will be/was loaded
  def contract_class_name
    @contract_class_name ||= if entity_slug
      entity_slug.split("_").map(&:capitalize).join << "Contract"
    else
      BLUEPRINT_CONTRACT_NAME
    end
  end

  private

  def entity_slug
    entity&.name.to_s.parameterize(separator: "_").presence
  end

  # Anonymous model-stub base shared by every placeholder model: a hash-backed
  # `attributes` bag with a no-op `save`. Each builder layers on only the extra
  # methods it needs ([]/[]=, destroy, persisted?, typed accessors).
  def base_model_stub
    Class.new do
      attr_accessor :attributes

      def initialize(attrs = {})
        @attributes = attrs
      end

      def save
        true
      end
    end
  end

  # Anonymous contract-stub base shared by the placeholder contracts: wraps a
  # model, exposes an empty `errors`, and delegates `save` to the model.
  def base_contract_stub
    Class.new do
      attr_reader :model, :errors

      def initialize(model)
        @model = model
        @errors = []
      end

      def save
        @model.save if @model.respond_to?(:save)
      end
    end
  end

  # Build entity model class from property_schema.
  # Mirrors EntityEntry interface: named accessors + hash-like [] / []=
  def build_entity_model(namespace)
    return if namespace.const_defined?(model_class_name.to_sym, false)

    schema = entity.property_schema_json || []
    slugs = schema.filter_map { |attr| attr["name_slug"] }.freeze

    model_class = base_model_stub
    model_class.define_method(:[]) { |key| @attributes[key.to_sym] }
    model_class.define_method(:[]=) { |key, value| @attributes[key.to_sym] = value }
    model_class.define_method(:destroy) { true }
    model_class.define_method(:persisted?) { false }

    # Define typed attribute accessors from property_schema
    slugs.each do |slug|
      model_class.define_method(slug) { @attributes[slug.to_sym] }
      model_class.define_method("#{slug}=") { |val| @attributes[slug.to_sym] = val }
    end

    namespace.const_set(model_class_name.to_sym, model_class)
  rescue StandardError => e
    log_warn "Failed to build entity model - #{e.message}"
    define_fallback_model(namespace)
  end

  # Build entity contract class using EntityEntryContract.build_for factory.
  # This creates a proper Reform::Form subclass with validations derived from
  # the entity's property_schema, enabling full Trailblazer Activity integration.
  def build_entity_contract(namespace)
    return if namespace.const_defined?(contract_class_name.to_sym, false)

    # Use the factory method to build a properly configured Reform contract
    contract_class = EntityEntryContract.build_for(entity)

    namespace.const_set(contract_class_name.to_sym, contract_class)
  rescue StandardError => e
    log_warn "Failed to build entity contract - #{e.message}"
    define_fallback_contract(namespace)
  end

  # Build blueprint model placeholder for flowcharts without bound entity.
  # Persistence is a no-op until an entity is bound.
  def build_blueprint_model(namespace)
    return if namespace.const_defined?(BLUEPRINT_MODEL_NAME, false)

    model_class = base_model_stub
    model_class.define_method(:destroy) { true }
    model_class.define_method(:persisted?) { false }

    namespace.const_set(BLUEPRINT_MODEL_NAME, model_class)
  end

  # Build blueprint contract placeholder for flowcharts without bound entity.
  # Validation just syncs params onto the model until an entity is bound.
  def build_blueprint_contract(namespace)
    return if namespace.const_defined?(BLUEPRINT_CONTRACT_NAME, false)

    contract_class = base_contract_stub
    contract_class.define_method(:validate) do |params|
      @model.attributes = params if @model.respond_to?(:attributes=)
      true
    end

    namespace.const_set(BLUEPRINT_CONTRACT_NAME, contract_class)
  end

  # Define fallback model when entity model building fails
  def define_fallback_model(namespace)
    return if namespace.const_defined?(model_class_name.to_sym, false)

    namespace.const_set(model_class_name.to_sym, base_model_stub)
  end

  # Define fallback contract when entity contract building fails
  def define_fallback_contract(namespace)
    return if namespace.const_defined?(contract_class_name.to_sym, false)

    contract_class = base_contract_stub
    contract_class.define_method(:validate) { |_params| true }

    namespace.const_set(contract_class_name.to_sym, contract_class)
  end
end
