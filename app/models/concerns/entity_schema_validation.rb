# frozen_string_literal: true

# Custom validations for Entity property schema, attribute groups, and associations.
module EntitySchemaValidation
  extend ActiveSupport::Concern

  included do
    validate :validate_definition_json_shapes
    validate :validate_unique_attribute_names
    validate :validate_unique_attribute_slugs
    validate :validate_attribute_slug_format
    validate :validate_attribute_groups_shape
    validate :validate_attribute_group_uniqueness
    validate :validate_attribute_group_references
    validate :validate_no_bridge_entity_conflicts
    validate :validate_no_duplicate_associations
    validate :validate_no_self_referential_associations
    validate :validate_association_display_field_present
    validate :validate_association_target_exists
    validate :validate_computed_definitions
    validate :validate_reference_definitions, if: :reference_definitions_changed?
    validate :validate_owner_reference, if: :reference_definitions_changed?
    validate :validate_referenced_display_fields, if: :referenced_display_fields_check?
  end

  private

  def definition_json_value(attribute, default:)
    raw = public_send(attribute)
    return default.deep_dup if raw.nil? || raw == ""

    raw.is_a?(String) ? JSON.parse(raw) : raw
  end

  def validate_definition_json_shapes
    { property_schema: Array, associations: Array, attribute_groups: Array, default_properties: Hash }.each do |attribute, shape|
      begin
        value = definition_json_value(attribute, default: shape.new)
        valid = value.is_a?(shape)
        valid &&= value.all? { |item| item.is_a?(Hash) } if shape == Array
        errors.add(attribute, :invalid) unless valid
      rescue JSON::ParserError
        errors.add(attribute, :invalid)
      end
    end

    schema_attributes.each { |field| validate_schema_item(field, :property_schema) }
    associations_list.each do |association|
      errors.add(:associations, :blank) if !bridge_entity? && association["target_entity_id"].blank?
      %w[target_entity_id bridge_entity_id].each do |key|
        value = association[key]
        next if value.nil? || value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))

        errors.add(:associations, :invalid)
      end
      additional = association["additional_attributes"]
      next if additional.nil?

      unless additional.is_a?(Array) && additional.all? { |field| field.is_a?(Hash) }
        errors.add(:associations, :invalid)
        next
      end
      additional.each { |field| validate_schema_item(field, :associations) }
    end
  end

  def validate_schema_item(field, attribute)
    errors.add(attribute, :blank) if field["name_slug"].blank?
    errors.add(attribute, :invalid) if !field["config"].nil? && !field["config"].is_a?(Hash)
    return if field["name_slug"].is_a?(String) && field["name_slug"].match?(ATTRIBUTE_SLUG_RE)

    errors.add(attribute, :invalid)
  end

  def schema_attributes
    value = property_schema_json
    value.is_a?(Array) ? value.select { |field| field.is_a?(Hash) } : []
  end

  def validate_unique_attribute_names
    duplicates = find_duplicates(attribute_values_for("name"))
    errors.add(:property_schema, I18n.t("maint_core.errors.validations.property_schema_duplicate_names", duplicates: duplicates.join(", "))) if duplicates.any?
  end

  def validate_unique_attribute_slugs
    duplicates = find_duplicates(attribute_values_for("name_slug"))
    errors.add(:property_schema, I18n.t("maint_core.errors.validations.property_schema_duplicate_slugs", duplicates: duplicates.join(", "))) if duplicates.any?
  end

  # An attribute slug is interpolated into SQL as a json_extract path and as a
  # computed-column alias, so it must be a bare identifier. The client generates
  # slugs, but the hidden form field is author-controlled and must not be trusted.
  # Digit-leading slugs are allowed because String#parameterize produces them
  # (e.g. "2024_revenue").
  ATTRIBUTE_SLUG_RE = /\A\w+\z/

  def validate_attribute_slug_format
    offenders = attribute_values_for("name_slug").reject { |slug| slug.to_s.match?(ATTRIBUTE_SLUG_RE) }
    return if offenders.empty?

    errors.add(:property_schema, I18n.t("maint_core.errors.validations.property_schema_invalid_slugs",
                                        slugs: offenders.join(", ")))
  end

  def attribute_values_for(key)
    schema_attributes.filter_map { |attr| attr[key] }
  end

  def find_duplicates(array)
    array.group_by(&:itself).select { |_, v| v.size > 1 }.keys
  end

  # Reads attribute_groups directly from the column without going through the
  # memoized `attribute_groups_json` accessor. This avoids polluting the
  # JsonSerializable cache during validation (which would leave callers with a
  # stale parsed value if the raw column is rewritten by the same save).
  def parsed_attribute_groups
    value = attribute_groups_json
    value.is_a?(Array) ? value.select { |group| group.is_a?(Hash) } : []
  end

  def validate_attribute_groups_shape
    groups = parsed_attribute_groups || []
    groups.each_with_index do |g, i|
      label = I18n.t("maint_core.errors.validations.attribute_group_ordinal", n: i + 1)
      if !g.is_a?(Hash) || g["id"].to_s.strip.empty?
        errors.add(:attribute_groups, I18n.t("maint_core.errors.validations.attribute_group_id_blank", label: label))
        next
      end
      unless g["id"].to_s =~ /\A[A-Za-z0-9_\-]{1,50}\z/
        errors.add(:attribute_groups, I18n.t("maint_core.errors.validations.attribute_group_id_format", label: label))
        next
      end
      if g["name"].to_s.strip.empty? || g["name"].to_s.length > 60
        errors.add(:attribute_groups, I18n.t("maint_core.errors.validations.attribute_group_name_length", label: label))
      end
      unless EntityAttributeGroupOptions::ICONS.key?(g["icon"].to_s)
        errors.add(:attribute_groups, I18n.t("maint_core.errors.validations.attribute_group_icon_not_allowed", label: label, icon: g["icon"]))
      end
      unless EntityAttributeGroupOptions::COLORS.include?(g["color"].to_s)
        errors.add(:attribute_groups, I18n.t("maint_core.errors.validations.attribute_group_color_not_allowed", label: label, color: g["color"]))
      end
    end
  end

  def validate_attribute_group_uniqueness
    groups = parsed_attribute_groups || []
    ids   = find_duplicates(groups.map { |g| g["id"].to_s })
    names = find_duplicates(groups.map { |g| g["name"].to_s.strip.downcase })
    errors.add(:attribute_groups, I18n.t("maint_core.errors.validations.attribute_groups_duplicate_ids", ids: ids.join(", "))) if ids.any?
    errors.add(:attribute_groups, I18n.t("maint_core.errors.validations.attribute_groups_duplicate_names", names: names.join(", "))) if names.any?
  end

  def validate_attribute_group_references
    known_ids = Set.new((parsed_attribute_groups || []).map { |g| g["id"].to_s })
    schema_attributes.each do |attr|
      gid = attr["group_id"]
      next if gid.nil? || gid.to_s.empty?
      unless known_ids.include?(gid.to_s)
        errors.add(:property_schema, I18n.t("maint_core.errors.validations.attribute_unknown_group_id", name: attr["name"], group_id: gid))
      end
    end
  end

  def validate_no_bridge_entity_conflicts
    return if bridge_entity?

    associations = associations_list
    return if associations.empty?

    conflicts = []
    associations.each do |assoc|
      target_entity_id = assoc["target_entity_id"]
      next unless target_entity_id

      target_entity = Entity.where(customer_id: customer_id).or(Entity.shared).find_by(id: target_entity_id.to_s)
      next unless target_entity

      bridge_name = generate_bridge_name(name, target_entity.name)
      existing_bridge_id = assoc["bridge_entity_id"]&.to_s
      conflicting_entity = Entity.unscope(:where)
                                 .where(customer_id: customer_id, name: bridge_name)
                                 .where.not(id: existing_bridge_id)
                                 .first
      next unless conflicting_entity

      status_info = conflicting_entity.inactive? ? I18n.t("maint_core.errors.validations.in_trash_suffix") : ""
      conflicts << I18n.t("maint_core.errors.validations.bridge_entity_conflict",
                           bridge_name: bridge_name, target_name: target_entity.display_label,
                           conflicting_name: conflicting_entity.display_label, status_info: status_info)
    end

    if conflicts.any?
      errors.add(:associations, I18n.t("maint_core.errors.validations.bridge_entity_conflicts_summary", conflicts: conflicts.join(". ")))
    end
  end

  def validate_no_duplicate_associations
    return if bridge_entity?

    assocs = associations_list
    return if assocs.empty?

    seen    = {}
    dupes   = []

    assocs.each do |assoc|
      tid    = assoc["target_entity_id"].to_s
      dfield = assoc["display_field"].to_s.strip
      key    = "#{tid}|#{dfield}"
      if seen[key]
        dupes << key unless dupes.include?(key)
      else
        seen[key] = true
      end
    end

    if dupes.any?
      errors.add(:associations, I18n.t("maint_core.errors.validations.associations_duplicate_target_display_field", dupes: dupes.join(", ")))
    end
  end

  def validate_no_self_referential_associations
    return if bridge_entity?
    return if id.nil?

    if associations_list.any? { |a| a["target_entity_id"].to_s == id.to_s }
      errors.add(:associations, I18n.t("maint_core.errors.validations.association_self_reference"))
    end
  end

  def validate_association_display_field_present
    return if bridge_entity?

    assocs = associations_list
    return if assocs.empty?

    assocs.each do |assoc|
      next if assoc["target_entity_id"].to_s.blank?

      display_field       = assoc["display_field"].to_s.strip
      display_field_label = assoc["display_field_label"].to_s.strip

      if display_field.blank? || display_field_label.blank?
        target_name = assoc["target_entity_name"].presence || assoc["target_entity_id"].to_s
        errors.add(:associations, I18n.t("maint_core.errors.validations.association_missing_display_field", target_name: target_name))
      end
    end
  end

  def validate_association_target_exists
    return if bridge_entity?

    assocs = associations_list
    return if assocs.empty?

    # Look across all statuses (incl. soft-deleted) so that a soft-deleted
    # target does not lock the source entity out of being edited; the user must
    # still be able to remove the broken association.  Cross-tenant targets
    # are still rejected.
    assocs.each do |assoc|
      tid = assoc["target_entity_id"].to_s.strip
      next if tid.blank?

      unless Entity.unscope(where: :status)
                    .where(customer_id: customer_id)
                    .or(Entity.unscope(where: :status).shared)
                    .exists?(id: tid)
        errors.add(:associations, I18n.t("maint_core.errors.validations.association_target_not_found", target_id: tid))
      end
    end
  end

  # Definition edits only: a status-only save (trash, restore) never fails on
  # a reference whose target went away in the meantime.
  def reference_definitions_changed?
    new_record? || will_save_change_to_property_schema? || will_save_change_to_associations?
  end

  def validate_reference_definitions
    reference_attributes.each { |attr| validate_reference_attribute(attr) }
    validate_association_display_fields unless bridge_entity?
  end

  # "owner": true is allowed on at most one reference whose target
  # is a person entity. Person entities, bridges, extras, and non-person
  # references cannot carry the flag.
  def validate_owner_reference
    flagged = owner_flagged_attributes
    return if flagged.empty?

    if flagged.size > 1
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.entity_owner_reference_multiple"))
      return
    end

    attr, from_association = flagged.first
    # EntityDefinitions::Persist saves a named target first and resolves its id
    # in a second save, which runs this check against the resolved reference.
    return if attr.dig("config", EntityDefinitions::ChoiceList::ENTITY_NAME_KEY).present?
    return if owner_flag_allowed?(attr, from_association: from_association)

    errors.add(:property_schema, I18n.t("maint_core.errors.validations.entity_owner_reference_invalid",
                                        field: owner_field_label(attr)))
  end

  def owner_flagged_attributes
    schema = schema_attributes.filter_map do |attr|
      next unless attr["owner"] == true

      [attr, false]
    end
    extras = associations_list.flat_map { |assoc| Array(assoc["additional_attributes"]) }.filter_map do |attr|
      next unless attr.is_a?(Hash) && attr["owner"] == true

      [attr, true]
    end
    schema + extras
  end

  def owner_flag_allowed?(attr, from_association:)
    return false if from_association || person? || bridge_entity?
    return false unless Entities::ReferenceLabels.reference?(attr) || attr["type"] == Entity::ENTITY_REFERENCE_TYPE

    target_id = attr.dig("config", "entity_id").presence || attr["entity_id"]
    reference_target(target_id)&.person?
  end

  def owner_field_label(attr)
    attr["display_label"].presence || attr["name"].presence || attr["name_slug"].to_s
  end

  # Entity-records dropdowns, including an association's extra attributes.
  def reference_attributes
    extras = associations_list.flat_map { |assoc| Array(assoc["additional_attributes"]) }
    (schema_attributes + extras).select { |attr| Entities::ReferenceLabels.reference?(attr) }
  end

  def validate_reference_attribute(attr)
    field = attr["display_label"].presence || attr["name"].presence || attr["name_slug"].to_s
    target = reference_target(attr.dig("config", "entity_id"))
    unless target
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.reference_target_missing", field: field))
      return
    end

    label_field = attr.dig("config", "label_field").to_s
    return if Entities::ReferenceLabels.labelable?(attribute_on(target, label_field))

    errors.add(:property_schema, I18n.t("maint_core.errors.validations.reference_label_field_invalid",
                                        field: field, label: attribute_name_on(target, label_field),
                                        entity: target.display_label))
  end

  # A blank display field and a missing target are reported by
  # validate_association_display_field_present / validate_association_target_exists.
  def validate_association_display_fields
    associations_list.each do |assoc|
      display_field = assoc["display_field"].to_s.strip
      target = reference_target(assoc["target_entity_id"])
      next if display_field.empty? || target.nil?
      next if Entities::ReferenceLabels.labelable?(attribute_on(target, display_field))

      errors.add(:associations, I18n.t("maint_core.errors.validations.association_display_field_invalid",
                                       target_name: target.display_label,
                                       label: assoc["display_field_label"].presence || display_field))
    end
  end

  # Any status, so restoring after a target was trashed still works. A shared
  # default may target shared entities; a customer's entity or a tenant's
  # override may also target that customer's own.
  def reference_target(target_id)
    id = target_id.to_s.strip
    return unless id.match?(/\A\d+\z/)
    return self if persisted? && id == self.id.to_s

    owner = customer_id || override_customer_id
    Entity.unscope(where: :status).where(customer_id: [owner, nil].uniq).find_by(id: id)
  end

  # A self-reference reads the schema being saved, not the stored one.
  def attribute_on(target, slug)
    schema = target.equal?(self) ? schema_attributes : Array(target.property_schema_json)
    schema.find { |attr| attr.is_a?(Hash) && attr["name_slug"].to_s == slug.to_s }
  end

  def attribute_name_on(target, slug)
    attribute_on(target, slug)&.dig("name").presence || slug.to_s
  end

  def referenced_display_fields_check?
    persisted? && !bridge_entity? && will_save_change_to_property_schema?
  end

  # A display field others rely on must stay labelable, and visible to every
  # audience of a launched form that lists it. Only a change that breaks a
  # working reference is refused, so an existing inconsistency never blocks
  # unrelated edits.
  def validate_referenced_display_fields
    dependents = Entities::ReferenceDependents.for_save(self)
    current = schema_attributes.grep(Hash).index_by { |attr| attr["name_slug"].to_s }
    previous = Array(JSON.parse(property_schema_was.presence || "[]")).grep(Hash).index_by { |attr| attr["name_slug"].to_s }

    dependents.references.group_by(&:label_field).each do |slug, refs|
      next if slug.blank? || !Entities::ReferenceLabels.labelable?(previous[slug])
      next if Entities::ReferenceLabels.labelable?(current[slug])

      errors.add(:property_schema, I18n.t("maint_core.errors.validations.display_field_in_use",
                                          label: previous[slug]["name"].presence || slug,
                                          fields: Entities::ReferenceDependents.field_paths(refs).to_sentence))
    end

    current.each do |slug, attr|
      next unless previous[slug]

      dependents.forms(slug).each do |form|
        audience = form.audiences.find do |aud|
          EntityAttributeAudience.visible_to?(previous[slug], aud) && !EntityAttributeAudience.visible_to?(attr, aud)
        end
        next unless audience

        errors.add(:property_schema, I18n.t("maint_core.errors.validations.display_field_hidden_from_form",
                                            label: attr["name"].presence || slug, audience: I18n.t("common.visibility.#{audience}"),
                                            form: form.page.name, field: form.field_label))
      end
    end
  rescue JSON::ParserError
    nil
  end

  def validate_computed_definitions
    schema_attributes.each do |field|
      next unless field.is_a?(Hash) && field["type"] == Entity::COMPUTED_TYPE

      name = field["name"].presence || field["name_slug"].presence || Entity::COMPUTED_TYPE
      validate_one_computed_field(field, name)
    end
  end

  def validate_one_computed_field(field, name)
    unless customer_owned?
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_not_customer_specific", name: name))
    end

    config = field["config"]
    unless config.is_a?(Hash)
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_config_invalid", name: name))
      return
    end

    unless Entities::ComputedCompiler::FUNCTIONS.include?(config["function"].to_s)
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_function_invalid", name: name))
    end

    unless computed_precision_ok?(config["precision"])
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_precision_invalid", name: name))
    end

    # During historical promotion the bridge may still be retired or have a
    # newer schema. Validate these contextual references after reconciliation;
    # the candidate's JSON/config shape is always validated first.
    return if validation_context == :promotion_candidate

    bridge = Entity.where(customer_id: customer_id, category: :bridge)
                   .find_by(id: config["bridge_entity_id"].to_s.to_i)
    unless bridge
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_bridge_not_found", name: name))
      return
    end

    schema = Array(bridge.property_schema_json)
    validate_computed_role(config, schema, name)
    validate_computed_source(config, schema, name)
    validate_computed_filter(config["filter"], schema, name)
  end

  def computed_precision_ok?(raw)
    return true if raw.nil?

    int = if raw.is_a?(Integer)
      raw
    elsif raw.to_s.match?(/\A\d+\z/)
      raw.to_i
    end
    int&.between?(0, Entities::ComputedCompiler::MAX_PRECISION)
  end

  def validate_computed_role(config, schema, name)
    idx = Entities::ComputedDefinition.role_index(config["bridge_role"])
    if idx.nil?
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_role_invalid", name: name))
      return
    end

    return if new_record?

    ref = schema[idx]
    return if ref.is_a?(Hash) && ref["entity_id"].to_s == id.to_s

    errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_host_not_participant", name: name))
  end

  def validate_computed_source(config, schema, name)
    function = config["function"].to_s
    source_slug = config["source_slug"].to_s
    source_attr = schema.find { |attr| attr.is_a?(Hash) && attr["name_slug"] == source_slug }

    if function != "count" && source_slug.blank?
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_source_missing", name: name))
      return
    end

    return if source_slug.blank?

    unless source_attr
      errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_source_unknown", name: name))
      return
    end

    return unless %w[avg sum min max].include?(function)
    return if Entities::ComputedCompiler::NUMERIC_HTML_TYPES.include?(source_attr["html_type"].to_s)

    errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_source_not_numeric", name: name))
  end

  def validate_computed_filter(filter, schema, name)
    return if filter.nil?

    valid = filter.is_a?(Hash) &&
            schema.any? { |attr| attr.is_a?(Hash) && attr["name_slug"] == filter["slug"].to_s } &&
            Entities::ComputedCompiler::FILTER_OPS.include?(filter["op"].to_s)
    return if valid

    errors.add(:property_schema, I18n.t("maint_core.errors.validations.computed_filter_invalid", name: name))
  end
end
