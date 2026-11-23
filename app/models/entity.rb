# frozen_string_literal: true

class Entity < ApplicationRecord
  include SoftDeletable
  include JsonSerializable
  include TenantScoped
  include SharedIdentity
  include BridgeEntityManagement
  include EntitySchemaValidation
  include Versionable

  # ==========================================================================
  # Configuration
  # ==========================================================================

  soft_deletable deleted_status: :inactive

  # Definition body: virtual attributes backed by the head version's content.
  # Declared as Rails attributes (not DB columns) so ActiveModel::Dirty
  # tracking, json_attribute, and BridgeEntityManagement keep working after the
  # columns are dropped. Populated from current_version.content on #after_find.
  attribute :property_schema,     :string
  attribute :default_properties,  :string
  attribute :associations,        :string
  # attribute_groups was a :json column historically (callers assign raw arrays),
  # so keep that type for the virtual attribute; the others were :text (strings).
  attribute :attribute_groups,    :json
  attribute :icon,                :string, default: "custom"
  attribute :color,               :string, default: "#6366f1"
  attribute :description,         :string
  attribute :referenced_template, :string

  json_attribute :property_schema,    default: []
  json_attribute :default_properties, default: {}
  json_attribute :associations,       default: []
  json_attribute :attribute_groups,   default: []
  # Invalid JSON stays invalid instead of becoming an empty valid definition.
  { property_schema: [], default_properties: {}, associations: [], attribute_groups: [] }.each do |attribute, default|
    define_method("#{attribute}_json") do
      raw = public_send(attribute)
      ivar = "@#{attribute}_json"
      raw_ivar = "@#{attribute}_json_raw"
      return instance_variable_get(ivar) if instance_variable_defined?(ivar) && instance_variable_get(raw_ivar) == raw

      instance_variable_set(raw_ivar, raw)
      instance_variable_set(ivar, definition_json_value(attribute, default: default))
    rescue JSON::ParserError
      instance_variable_set(ivar, nil)
    end
  end

  # ==========================================================================
  # Versioning
  # ==========================================================================

  acts_as_versionable reflection: :entity_versions,
                      version_class: "EntityVersion",
                      content_class: "EntityDefinitionContent",
                      snapshot_reader: :definition_snapshot_json,
                      customer_head_reflection: :entity_customer_heads

  after_find :reload_definition_from_head!

  # ==========================================================================
  # Enums
  # ==========================================================================

  enum :status, { active: 0, inactive: 1 }, default: :active

  # Structural category (replaces the old is_bridge_entity boolean):
  #   plain     — a normal entity
  #   bridge    — a junction entity materializing an entity↔entity association
  #   extension — an entity that extends a base AR model
  enum :category, { plain: 0, bridge: 1, extension: 2 },
       default: :plain, prefix: :category

  # ==========================================================================
  # Associations
  # ==========================================================================

  has_many :entity_entries, dependent: :destroy
  has_many :entity_index_settings, dependent: :destroy
  has_many :entity_domain_memberships, dependent: :delete_all

  # ==========================================================================
  # Callbacks
  # ==========================================================================

  before_validation :assign_category_from_extended_model
  before_validation :default_display_label_from_name
  before_destroy :prevent_referenced_shared_entity_destruction, prepend: true

  # ==========================================================================
  # Validations
  # ==========================================================================

  validates :name,
            presence: true,
            length: { minimum: 1, maximum: 100 }
  validates :display_label,
            presence: true,
            length: { maximum: 100 }

  validate :shared_entity_has_no_associations
  validate :bridge_entity_has_no_extended_model
  validate :extended_model_is_approved
  validate :person_extension_is_permanent

  # ==========================================================================
  # Scopes
  # ==========================================================================

  scope :by_name, -> { order(:name) }
  scope :recent, -> { order(created_at: :desc) }
  scope :search_by_name, ->(query) {
    query = Array.wrap(query).join(" ").strip
    return all if query.blank?
    where("LOWER(name) LIKE ?", "%#{query.downcase}%")
  }
  scope :search_by_display_label, ->(query) {
    query = Array.wrap(query).join(" ").strip
    return all if query.blank?
    where("LOWER(display_label) LIKE ?", "%#{query.downcase}%")
  }
  scope :non_bridge, -> { where.not(category: :bridge) }

  default_scope { visible }

  # ==========================================================================
  # Public Methods
  # ==========================================================================

  # The canonical definition hash stored in a version's content. name is NOT
  # included — it is an un-versioned identity column on the parent.
  def definition_snapshot
    {
      "icon"                => icon,
      "color"               => color,
      "description"         => description,
      "property_schema"     => property_schema_json     || [],
      "default_properties"  => default_properties_json  || {},
      "associations"        => associations_json        || [],
      "attribute_groups"    => attribute_groups_json    || [],
      "referenced_template" => referenced_template
    }
  end

  def definition_snapshot_json = definition_snapshot.to_json

  def restore_as_new!(version)
    result = Entities::PromoteVersion.call(entity: self, version: version, restore: true)
    raise ActiveRecord::RecordInvalid, self unless result.success?

    result.version
  end

  def set_current_version!(version)
    result = Entities::PromoteVersion.call(entity: self, version: version, restore: false)
    raise ActiveRecord::RecordInvalid, self unless result.success?

    result.version
  end

  # Populate the virtual definition attributes from the current head content.
  # Called on after_find and after the head moves (restore / set-current).
  def reload_definition_from_head!
    payload = resolved_current_version&.content&.payload
    snap = payload.present? ? JSON.parse(payload) : {}
    self.icon                = snap.fetch("icon", "custom")
    self.color               = snap.fetch("color", "#6366f1")
    self.description         = snap["description"]
    self.referenced_template = snap["referenced_template"]
    # Use the *_json= setters so json_attribute's memoized parse is cleared.
    self.property_schema_json    = snap["property_schema"]    || []
    self.default_properties_json = snap["default_properties"] || {}
    self.associations_json       = snap["associations"]       || []
    self.attribute_groups_json   = snap["attribute_groups"]   || []
    # The loaded state is the baseline for Dirty tracking, so a subsequent edit
    # is diffed against the head content (BridgeEntityManagement relies on this).
    clear_changes_information if persisted?
    self
  end

  def as_palette_item
    {
      id: id,
      name: display_label,
      element_type: "custom_#{id}",
      icon: icon,
      color: color,
      description: description,
      default_properties: default_properties_json || {},
      property_schema: property_schema_json || []
    }
  end

  # Restore entity and cascade to its bridge entities
  def restore
    restored = false
    self.class.transaction(requires_new: true) do
      raise ActiveRecord::Rollback unless super
      raise ActiveRecord::Rollback unless bridge_entity? || restore_bridge_entities!

      restored = true
    end
    unless restored
      failures = errors.dup
      reload
      errors.copy!(failures)
    end
    restored
  rescue ActiveRecord::RecordNotUnique
    reload
    errors.add(:name, :taken)
    false
  end

  def associations_list
    value = associations_json
    value.is_a?(Array) ? value.select { |association| association.is_a?(Hash) } : []
  end

  def has_associations?
    associations_list.any?
  end

  def bridge_entity?
    category_bridge?
  end

  # A person entity extends Authentication::User. Bridge junctions never qualify,
  # even if extended_model is somehow set.
  def person?
    !bridge_entity? && extended_model == EntityDefinitions::Capabilities::PERSON_MODEL
  end

  COMPUTED_TYPE = "Computed"
  ENTITY_REFERENCE_TYPE = "EntityReference"

  # Returns calculated field definitions from property_schema.
  def calculated_fields
    schema_attributes.select { |f| f["type"] == "Calculated" }
  end

  # Returns computed (bridge-aggregate) field definitions from property_schema.
  def computed_fields
    schema_attributes.select { |f| f["type"] == COMPUTED_TYPE }
  end

  # Returns stored input field definitions (excludes Calculated and Computed).
  def input_fields
    schema_attributes.reject { |f| %w[Calculated Computed].include?(f["type"]) }
  end

  # Returns [{ group: <hash or nil>, attributes: [...] }, ...] preserving group order.
  # Ungrouped attributes appear last as a section with group: nil.
  def grouped_property_schema
    groups = parsed_attribute_groups
    attrs  = schema_attributes
    by_id  = attrs.group_by { |a| a["group_id"].presence }

    sections = groups.map { |g| { group: g, attributes: by_id[g["id"]] || [] } }
    ungrouped = by_id[nil]
    sections << { group: nil, attributes: ungrouped } if ungrouped.present?
    sections
  end

  def searchable_field_keys
    schema = attributes_before_type_cast["property_schema"]
    schema = case schema
    when Array
               schema
    when String
               JSON.parse(schema) rescue []
    else
               []
    end

    schema
      .select { |f| %w[string text].include?(f["type"]) }
      .first(3)
      .map { |f| f["key"] }
  end

  def sortable_field_keys
    searchable_field_keys + %w[created_at updated_at]
  end

  private

  def prevent_referenced_shared_entity_destruction
    return unless shared? && entities_referencing_as_target.unscope(where: :status).exists?

    errors.add(:base, I18n.t("maint_core.errors.validations.entity_has_associations"))
    throw :abort
  end

  # Only the entity promotion activity calls this after candidate validation
  # and bridge reconciliation. It does not alter generic builder behavior.
  def promote_validated_line_head!(version)
    promote_line_head!(override_customer_id, version)
  end

  def extended_model_is_approved
    return if extended_model.blank? || category_bridge?

    approved = ExtendableModelRegistry.for_customer(customer_id).any? do |definition|
      definition[:class_name] == extended_model
    end
    model = extended_model.safe_constantize if approved
    return if model.is_a?(Class) && model < ActiveRecord::Base && !model.abstract_class?

    errors.add(:extended_model, :inclusion)
  end

  # Entries of a person entity are linked to sign-in accounts, so once an
  # entity extends the person model it can never be switched or cleared.
  def person_extension_is_permanent
    return unless extended_model_changed? && extended_model_was == EntityDefinitions::Capabilities::PERSON_MODEL

    errors.add(:extended_model, I18n.t("maint_core.errors.validations.person_extension_permanent"))
  end

  def shared_entity_has_no_associations
    return unless shared?
    return unless associations_list.any?

    errors.add(:base, I18n.t("maint_core.errors.validations.entity_shared_no_associations"))
  end

  # Category is DERIVED from the extension relationship: selecting a base model
  # (setting `extended_model`) makes the entity an :extension; clearing it makes
  # it :plain. Bridge entities are classified by BridgeEntityManagement and are
  # never derived here. An entity extends at most one base model — guaranteed
  # structurally by the single `extended_model` column.
  def assign_category_from_extended_model
    self.extended_model = extended_model.presence
    return if category_bridge?

    self.category = extended_model.present? ? :extension : :plain
  end

  # Safety net: a bridge entity is a junction and never extends a base model.
  def bridge_entity_has_no_extended_model
    return unless category_bridge? && extended_model.present?

    errors.add(:extended_model, I18n.t("maint_core.errors.validations.extended_model_forbidden_on_bridge"))
  end

  # Display Label defaults to the internal name unless the user has edited it.
  # If the name changes and the display label still matches the previous name,
  # keep it mirrored; otherwise preserve the manually-edited label.
  def default_display_label_from_name
    if display_label.blank?
      self.display_label = name
    elsif name_changed? && display_label == name_was.to_s
      self.display_label = name
    end
  end
end
