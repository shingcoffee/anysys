# frozen_string_literal: true

# EntityEntry
#
# Persistent record model for entity instances. Stores variable-length
# attribute key-value pairs in a single JSON `data` column.
#
# Schema: id | entity_id | data (JSON) | created_at | updated_at
#
# Provides four complementary levels of attribute access via Ruby
# metaprogramming (each serves a distinct caller and they are NOT
# interchangeable — e.g. only build_for exposes read-only Calculated fields):
#
#   1. Factory method `build_for(entity)` - creates entity-specific subclass
#      with typed attribute accessors at runtime (for Trailblazer Activities)
#
#      model_class = EntityEntry.build_for(entity)
#      entry = model_class.new
#
#   2. Class DSL `attribute_accessor` - dynamically extends EntityEntry
#      via class_eval (see ModelGenerator)
#
#      EntityEntry.class_eval do
#        attribute_accessor :name, :string
#      end
#
#   3. Hash-like access via `[]` / `[]=`
#      entry[:name] = "Alice"
#      entry[:name]  # => "Alice"
#
#   4. Dynamic dispatch via `method_missing` - any key in the entity's
#      property_schema is accessible as a method
#      entry.name = "Alice"
#      entry.name  # => "Alice"
#
class EntityEntry < ApplicationRecord
  include JsonSerializable
  include TenantScoped
  include EntityEntryFiles

  json_attribute :data, default: {}
  # customer_id is required for tenant isolation

  belongs_to :entity
  belongs_to :user, class_name: "Authentication::User", optional: true, inverse_of: :person_entries
  has_many :feature_module_logs, -> { unscope(where: :customer_id) },
           class_name: "FeatureModules::Log", dependent: :nullify

  validates :customer_id, presence: true

  validate :validate_data_keys

  # Every entry column and association answers to its own name, so a data
  # attribute by one of these names could never be read or written.
  def self.reserved_attribute_slugs
    @reserved_attribute_slugs ||= (column_names + reflect_on_all_associations.map { |assoc| assoc.name.to_s }).to_set.freeze
  end

  def self.reserved_attribute_slug?(slug) = EntityEntry.reserved_attribute_slugs.include?(slug.to_s)

  # The slug an attribute named +name+ gets when none is given, such as a
  # bridge's participant named after its entity: "_ref" keeps a name like
  # "Customer" clear of the reserved ones.
  def self.attribute_slug_for(name)
    slug = name.to_s.parameterize(separator: "_")
    reserved_attribute_slug?(slug) ? "#{slug}_ref" : slug
  end

  # Provenance: stamp the entity definition version_number in effect at creation.
  # before_create is the single choke point every creation path flows through
  # (flowchart runtime, imports, console), so the stamp is captured once and
  # frozen — later entity edits never mutate an existing entry's stamp.
  #
  # The assignment is authoritative (not ||=): entity_version_number is a real
  # column, so EntityEntry#[]= routes it to the AR setter, and the entity-params
  # path (FormParamsRouter → PopulatePrimary) does not whitelist keys to the
  # schema. A crafted submission (entity[entity_version_number]=…) would
  # otherwise forge the stamp. Overwriting from the true head here closes that
  # vector. Provenance only: rendering/validation still resolve against the head.
  before_create :stamp_entity_version
  after_save :reset_derived_values!
  before_destroy :delete_referencing_bridge_entries, prepend: true

  # ==========================================================================
  # Class-level Factory
  # ==========================================================================

  # Factory method to build an entity-specific model subclass.
  # Creates a new subclass with typed attribute accessors derived from
  # the entity's property_schema.
  #
  # @param entity [Entity] the entity defining the property schema
  # @return [Class] a subclass of EntityEntry configured for the entity
  #
  # @example Building a model for an entity in Trailblazer Activity
  #   model_class = EntityEntry.build_for(entity)
  #   entry = model_class.new
  #   entry.email = "test@example.com"
  #   entry.save
  #
  def self.build_for(entity)
    return self if entity.nil?

    schema = entity.property_schema_json || []
    internal_attributes = column_names + %w[entity customer]

    Class.new(self) do
      # Store bound entity reference
      @bound_entity = entity

      class << self
        attr_reader :bound_entity

        # Anonymous runtime classes retain the parent's Rails/I18n identity.
        def name
          EntityEntry.name
        end

        def model_name
          EntityEntry.model_name
        end

        # Override table_name to use parent's table
        def table_name
          EntityEntry.table_name
        end

        # Ensure STI doesn't interfere
        def sti_name
          "EntityEntry"
        end
      end

      # Define typed attribute accessors from property_schema
      # (Calculated and Computed fields are read-only — no writer is generated;
      # File and Image fields are attachments, see EntityEntryFiles).
      schema.each do |attr|
        slug = attr["name_slug"]
        next unless slug
        # Definition data cannot shadow authoritative AR columns/associations.
        next if internal_attributes.include?(slug)

        if file_attribute?(attr)
          declare_file_attachment(attr)
        else
          define_data_accessor(slug, writable: !%w[Calculated Computed].include?(attr["type"]))
        end
      end

      # Hook into after_initialize to set entity association
      after_initialize do
        self.entity ||= self.class.bound_entity
      end
    end
  end

  # ==========================================================================
  # Class-level DSL
  # ==========================================================================

  # Declares a typed attribute accessor backed by the JSON data column.
  # Used via class_eval to dynamically extend EntityEntry (see ModelGenerator).
  #
  # @param name [Symbol] attribute name (must match a property_schema name_slug)
  # @param _type [Symbol] type annotation (for documentation; not enforced at runtime)
  def self.attribute_accessor(name, _type = :string)
    define_data_accessor(name.to_s)
  end

  # Defines a JSON-`data`-backed reader (and, unless read-only, writer) for
  # `name`. Shared by build_for's per-schema accessors and the
  # attribute_accessor DSL so the getter/setter bodies live in one place.
  def self.define_data_accessor(name, writable: true)
    name = name.to_s
    if writable
      define_method(name) { data_json[name] }
      define_method("#{name}=") { |value| merge_data(name => value) }
    else
      define_method(name) { flowchart_value(name) }
    end
  end

  # ==========================================================================
  # Hash-like access
  # ==========================================================================

  # Derived (computed and calculated) values for this entry, never stored in
  # `data`. List paths call Entities::DerivedValues.prime! first so this is a
  # hash lookup; a lone record resolves here in one query.
  def prime_derived_values!(hash)
    @derived_values = hash.is_a?(Hash) ? hash : {}
  end

  # A new record has none until it is saved; saving or reloading reads them
  # again, as does a writer that changed the rows they sum up.
  def derived_values
    return @derived_values if @derived_values
    return {} if entity.nil? || id.nil?

    @derived_values = Entities::DerivedValues.call(entity: entity, customer_id: customer_id, entry_ids: [id]).fetch(id, {})
  end

  def reset_derived_values!
    @derived_values = nil
    self
  end

  def reload(...)
    reset_derived_values!
    super
  end

  # Display text through the Entities::EntryDisplay a list attached to this
  # entry (EntryDisplay.prime!); the raw stored or derived value without one.
  def prime_display!(display)
    @entry_display = display
  end

  def display_text(slug)
    return @entry_display.text(self, slug) if @entry_display

    key = slug.to_s
    data_json.key?(key) ? data_json[key] : derived_values[key]
  end

  # A flowchart's paths (FlowchartRuntime::Step.dig) and Liquid templates
  # read a record as its id and its stored and derived values. A path reads
  # a file field as its attachment (nil when it holds none); templates read
  # its filenames.
  def flowchart_value(key)
    key = key.to_s
    return id if key == "id"
    return public_send(key).presence if file_slug?(key)

    data_json.key?(key) ? data_json[key] : derived_values[key]
  end

  def to_liquid = derived_values.merge(data_json).merge(file_names).merge("id" => id)

  def [](key)
    has_attribute?(key) ? super : data_json[key.to_s]
  end

  def []=(key, value)
    has_attribute?(key) ? super : merge_data(key.to_s => value)
  end

  def linked?
    user_id.present?
  end

  # ==========================================================================
  # Dynamic attribute dispatch
  # ==========================================================================

  def method_missing(method_name, *args, &block)
    attr_name = method_name.to_s

    if attr_name.end_with?("=")
      key = attr_name.chomp("=")
      return super unless valid_attribute_slug?(key)

      merge_data(key => args.first)
    elsif valid_attribute_slug?(attr_name)
      data_json[attr_name]
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    valid_attribute_slug?(method_name.to_s.chomp("=")) || super
  end

  # Slugs this entry stores in `data` (never its derived ones).
  def valid_attribute_slugs
    @valid_attribute_slugs ||= begin
      schema = entity&.property_schema_json
      (schema.is_a?(Array) ? schema.select { |field| field.is_a?(Hash) } : [])
        .reject { |attr| %w[Calculated Computed].include?(attr["type"]) }
        .map { |attr| attr["name_slug"] }
    end
  end

  private

  # Participant references live in JSON rather than foreign keys. Delete only
  # junction records in this entry's tenant; a shared entity still has isolated
  # entry data for each customer. The visited set also tolerates legacy cycles.
  def delete_referencing_bridge_entries
    @_bridge_deletion_ids ||= Set.new
    return unless @_bridge_deletion_ids.add?(id)

    Entity.with_deleted.where(customer_id: customer_id).or(Entity.with_deleted.shared)
          .where(category: :bridge).find_each do |bridge|
      schema = bridge_schema_for_entry_customer(bridge)
      next unless schema.is_a?(Array)

      slugs = schema.filter_map do |field|
        next unless field.is_a?(Hash) && field["type"] == Entity::ENTITY_REFERENCE_TYPE
        next unless field["entity_id"].to_s == entity_id.to_s

        field["name_slug"] if field["name_slug"].is_a?(String)
      end
      next if slugs.empty?

      EntityEntry.where(customer_id: customer_id, entity_id: bridge.id).where.not(id: id).find_each do |entry|
        next if @_bridge_deletion_ids.include?(entry.id)

        data = entry.data_json
        next unless data.is_a?(Hash) && slugs.any? { |slug| bridge_reference_matches?(data[slug]) }

        # Cascading a junction's deletion cannot introduce another participant
        # edge in a valid schema; a shared visited set bounds malformed graphs.
        entry.instance_variable_set(:@_bridge_deletion_ids, @_bridge_deletion_ids)
        entry.destroy!
      end
    end
  ensure
    remove_instance_variable(:@_bridge_deletion_ids) if instance_variable_defined?(:@_bridge_deletion_ids)
  end

  def bridge_reference_matches?(value)
    value == id || (value.is_a?(String) && Integer(value, 10, exception: false) == id)
  end

  def bridge_schema_for_entry_customer(bridge)
    version = Current.set(shared_resources_mode: false) { bridge.resolved_current_version(customer_id) }
    snapshot = version&.payload.present? ? JSON.parse(version.payload) : {}
    snapshot.is_a?(Hash) ? snapshot["property_schema"] : nil
  rescue JSON::ParserError
    nil
  end

  # Records the entity's head version_number at insert time (provenance).
  # Authoritative: overwrites any client-supplied value (see before_create note).
  def stamp_entity_version
    self.entity_version_number = entity&.resolved_current_version&.version_number
  end

  # Merges attributes into the data JSON hash, properly resetting
  # the JsonSerializable memoization cache.
  def merge_data(attrs)
    updated = data_json.merge(attrs.transform_keys(&:to_s))
    # A JSON column encodes a String again, so give it the Hash. A text column
    # stores the encoded string, which is what the SQL readers expect.
    self.data = self.class.type_for_attribute(:data).type == :json ? updated : updated.to_json
    remove_instance_variable(:@data_json) if instance_variable_defined?(:@data_json)
  end

  def valid_attribute_slug?(key)
    valid_attribute_slugs.include?(key)
  end

  def validate_data_keys
    value = data.nil? || data == "" ? {} : (data.is_a?(String) ? JSON.parse(data) : data)
    unless value.is_a?(Hash)
      errors.add(:data, :invalid)
      return
    end
    return if value.blank?

    allowed_keys = valid_attribute_slugs
    allowed_keys += People::IDENTITY_KEYS if entity&.person?
    invalid_keys = value.keys - allowed_keys
    return if invalid_keys.empty?

    errors.add(:data, I18n.t("maint_core.errors.validations.data_invalid_keys", invalid_keys: invalid_keys.join(", ")))
  rescue JSON::ParserError
    errors.add(:data, :invalid)
  end
end
