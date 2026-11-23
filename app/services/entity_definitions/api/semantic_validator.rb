# frozen_string_literal: true

module EntityDefinitions
  module Api
    # Cross-field and reference rules for entity operations. Structural
    # checks belong to JSON Schema; policy/quota/role belong here too.
    class SemanticValidator
      MAX_VIOLATIONS = Operations::Schema::MAX_VIOLATIONS
      RESERVED_NAME_PREFIX = "assoc_"
      RESERVED_SLUGS = %w[id user_id].freeze
      SELECTION_TYPES = HtmlTypeOptions::SELECTION_TYPES
      FILE_TYPES = HtmlTypeOptions::CONFIG_TYPES.fetch(:file)
      NUMERIC_HTML_TYPES = Entities::ComputedCompiler::NUMERIC_HTML_TYPES
      FORMULA_FUNCTIONS = FlowchartRuntime::FormulaCompiler::SUPPORTED_FUNCTIONS.map(&:upcase).to_set
      SYSTEM_FIELDS = %w[id].freeze

      Target = Struct.new(:status, :record, :candidates, keyword_init: true) do
        # Why an operation cannot act on the named entity, or nil when it can.
        def violation(name:, pointer:)
          case status
          when :ok then nil
          when :in_trash
            Operations::Violation.new(pointer: pointer, code: "entity.name_in_trash", details: { "name" => name },
                                      resolution: "ask_user")
          when :not_editable
            Operations::Violation.new(pointer: pointer, code: "entity.not_editable", details: { "name" => name },
                                      resolution: "blocked")
          else
            Operations::Violation.new(
              pointer: pointer,
              code: "entity.not_found",
              details: { "name" => name, "candidates" => candidates },
              resolution: candidates.empty? ? "ask_user" : "fix_payload"
            )
          end
        end
      end

      def self.locate(customer:, name:)
        owned = Entity.unscope(where: :status).where(customer_id: customer.id, name: name).first
        if owned
          return Target.new(status: :in_trash, record: owned, candidates: []) if owned.inactive?
          return Target.new(status: :not_editable, record: owned, candidates: []) if owned.bridge_entity?

          return Target.new(status: :ok, record: owned, candidates: [])
        end

        shared = Entity.unscope(where: :status).shared.find_by(name: name)
        if shared
          return Target.new(status: :not_editable, record: shared, candidates: [])
        end

        dictionary = editable_names(customer)
        Target.new(
          status: :not_found,
          record: nil,
          candidates: Operations::Violation.candidates(name, dictionary)
        )
      end

      def self.editable_names(customer)
        Entity.where(customer_id: customer.id).non_bridge.by_name.pluck(:name)
      end

      def self.catalog_document(customer, name)
        Catalog.document_for(customer.id, name)
      end

      def self.for_create(specs, customer:)
        new(customer: customer, mode: :create).validate_create(specs)
      end

      def self.for_update(documents, customer:, origins: [])
        new(customer: customer, mode: :update, origins: origins).validate_update(documents)
      end

      def initialize(customer:, mode:, origins: [])
        @customer = customer
        @mode = mode
        @origins = origins
        @violations = []
        @mapper = Mapper.new(customer: customer)
      end

      def validate_create(specs)
        @specs = Array(specs).map { |spec| stringify(spec) }
        @pointer_base = "/entities"
        index_specs!
        check_create_identities
        check_quota
        check_person_entity
        @specs.each_with_index do |spec, index|
          validate_spec(spec, index)
          validate_base_model_slugs
        end
        @violations.first(MAX_VIOLATIONS)
      end

      def validate_update(documents)
        @specs = Array(documents).map { |doc| spec_from_document(doc) }
        @pointer_base = "/updates"
        index_specs!
        @specs.each_with_index do |spec, index|
          validate_spec(spec, index)
          validate_base_model_slugs
        end
        # Only an otherwise valid update reaches the guard, so every
        # attribute maps to a stored shape.
        @specs.each_with_index { |spec, index| guard_display_fields(spec, index) } if @violations.empty?
        @violations.first(MAX_VIOLATIONS)
      end

      private

      attr_reader :customer, :mapper

      def index_specs!
        @specs_by_name = @specs.index_by { |spec| spec["name"].to_s }
        @existing_names = SemanticValidator.editable_names(customer)
        @known_names = (@existing_names + @specs_by_name.keys).uniq
        @catalog = Catalog.for_customer(customer.id).index_by { |doc| doc["name"] }
      end

      def check_create_identities
        names = @specs.map { |spec| spec["name"].to_s.strip }
        names.tally.each do |name, count|
          next if name.blank? || count < 2

          @specs.each_with_index do |spec, index|
            next unless spec["name"].to_s.strip == name

            add("/entities/#{index}/name", "entity.duplicate_in_request", "name" => name)
          end
        end

        names.uniq.each do |name|
          next if name.blank?

          pointer = "/entities/#{names.index(name)}/name"
          if name.start_with?(RESERVED_NAME_PREFIX)
            add(pointer, "entity.name_reserved", "name" => name)
            next
          end

          existing = Entity.unscope(where: :status).where(customer_id: customer.id, name: name).first
          next unless existing

          if existing.inactive?
            add(pointer, "entity.name_in_trash", { "name" => name }, "ask_user")
          else
            add(pointer, "entity.already_exists", "name" => name)
          end
        end
      end

      def check_quota
        new_names = @specs.map { |spec| spec["name"].to_s.strip }.reject(&:blank?).uniq
        new_names.reject! do |name|
          Entity.unscope(where: :status).where(customer_id: customer.id, name: name).exists?
        end
        return if new_names.empty?
        return if Billing::Quota.for(customer).allow?("entity", by: new_names.size)

        add("/entities", "quota.exceeded")
      end

      # A create call extends the person model at most once, lists that
      # entity first, and declares the call's links on it, so its form is
      # the one that collects them.
      def check_person_entity
        people = @specs.each_index.select { |index| @specs[index]["extends"] == Capabilities::PERSON_MODEL }
        return if people.empty?

        primary, *extra = people
        person = @specs[primary]["name"].to_s
        extra.each do |index|
          add("/entities/#{index}/extends", "extends.person_not_unique",
              "name" => @specs[index]["name"], "primary" => person)
        end
        add("/entities/#{primary}", "entity.person_not_first", "name" => person) unless primary.zero?

        @specs.each_with_index do |spec, index|
          next if index == primary

          Array(spec["associations"]).each_with_index do |assoc, assoc_index|
            next unless assoc["related_entity"].to_s == person

            add("/entities/#{index}/associations/#{assoc_index}/related_entity", "association.person_not_primary",
                "name" => person, "entity" => spec["name"])
          end
        end
      end

      def validate_base_model_slugs
        model = @spec["extends"]
        return if model.blank?

        reserved = Capabilities.base_model_fields(customer.id, model)
        Array(@spec["attributes"]).each do |attr|
          slug = attribute_slug(attr)
          next unless reserved.include?(slug) && RESERVED_SLUGS.exclude?(slug)

          add(attr_pointer(attr, "slug"), "attribute.reserved_by_base_model", "slug" => slug, "model" => model)
        end
      end

      def validate_spec(spec, index)
        @entity_index = index
        @spec = spec
        validate_extends
        validate_groups
        validate_attributes
        validate_defaults
        validate_associations
        validate_computed_aggregates
        validate_owner_flags
      end

      def validate_extends
        value = @spec["extends"]
        return if value.blank?

        allowed = ExtendableModelRegistry.for_customer(customer.id).map { |row| row[:class_name] }
        return if allowed.include?(value)

        add(origin_or("details", @spec["name"], "extends"), "extends.not_allowed", "name" => value)
      end

      def validate_groups
        groups = Array(@spec["attribute_groups"])
        keys = groups.map { |group| group["key"].to_s }
        names = groups.map { |group| group["name"].to_s.strip.downcase }
        keys.tally.each do |key, count|
          next if key.blank? || count < 2

          add(origin_or("group", key, "key"), "group.duplicate_key", "key" => key)
        end
        names.tally.each do |name, count|
          next if name.blank? || count < 2

          group = groups.find { |row| row["name"].to_s.strip.downcase == name }
          add(origin_or("group", group["key"], "name"), "group.duplicate_name", "name" => group["name"])
        end
      end

      def validate_attributes
        attrs = Array(@spec["attributes"])
        names = attrs.map { |attr| attr["name"].to_s.strip }
        slugs = attrs.map { |attr| attribute_slug(attr) }
        names.tally.each do |name, count|
          next if name.blank? || count < 2

          add(attr_pointer(attrs.find { |attr| attr["name"].to_s.strip == name }, "name"), "attribute.duplicate_name", "name" => name)
        end
        slugs.tally.each do |slug, count|
          next if slug.blank? || count < 2

          add(attr_pointer(attrs.find { |attr| attribute_slug(attr) == slug }, "slug"), "attribute.duplicate_slug", "slug" => slug)
        end

        group_keys = Array(@spec["attribute_groups"]).map { |group| group["key"].to_s }
        attrs.each { |attr| validate_attribute(attr, slugs, group_keys) }
      end

      def validate_attribute(attr, slugs, group_keys)
        slug = attribute_slug(attr)
        if RESERVED_SLUGS.include?(slug) || slug.blank? || !slug.match?(/\A\w+\z/)
          add(attr_pointer(attr, "slug"), "attribute.reserved_slug", "slug" => slug)
        elsif EntityEntry.reserved_attribute_slug?(slug)
          add(attr_pointer(attr, "slug"), "attribute.reserved_by_record", "slug" => slug, "suggestion" => EntityEntry.attribute_slug_for(slug))
        end

        group = attr["group"]
        if group.present? && group_keys.exclude?(group.to_s)
          candidates = Operations::Violation.candidates(group, group_keys)
          add(attr_pointer(attr, "group"), "attribute.unknown_group", "group" => group, "candidates" => candidates)
        end

        html_type = attr["html_type"].presence || "text"
        kind = attr["kind"].presence || "input"
        validate_rules(attr, html_type)
        validate_options(attr, html_type)
        validate_file(attr, html_type)
        validate_formula(attr, kind, slugs)
        validate_lifecycle(attr, html_type, kind)
      end

      # States are the static option values; the one default option is where
      # a new record starts. Checked on the attribute as the call leaves it,
      # so an update that drops an option a transition names is caught too.
      def validate_lifecycle(attr, html_type, kind)
        lifecycle = attr["lifecycle"]
        return if lifecycle.blank?

        slug = attribute_slug(attr)
        options = stringify(attr["options"])
        unless kind == "input" && Entities::Lifecycle::CHOICE_TYPES.include?(html_type) && options["source"].to_s == "static"
          add(attr_pointer(attr, "lifecycle"), "entity.lifecycle_not_choice", "slug" => slug)
          return
        end

        values = Array(options["values"])
        defaults = values.count { |value| value.is_a?(Hash) && [true, "true"].include?(stringify(value)["default"]) }
        add(attr_pointer(attr, "options", "values"), "entity.lifecycle_initial_missing", "slug" => slug) unless defaults == 1

        states = values.filter_map { |value| option_stored_value(value) }
        seen = []
        Array(stringify(lifecycle)["transitions"]).each_with_index do |row, index|
          row = stringify(row)
          pair = [row["from"].to_s, row["to"].to_s]
          pair.zip(%w[from to]).each do |state, side|
            next if states.include?(state)

            add(attr_pointer(attr, "lifecycle", "transitions", index, side), "entity.lifecycle_unknown_state",
                "slug" => slug, "state" => state, "candidates" => Operations::Violation.candidates(state, states))
          end
          if pair.first == pair.last
            add(attr_pointer(attr, "lifecycle", "transitions", index), "entity.lifecycle_self_transition",
                "slug" => slug, "state" => pair.first)
          elsif seen.include?(pair)
            add(attr_pointer(attr, "lifecycle", "transitions", index), "entity.lifecycle_duplicate_transition",
                "slug" => slug, "from" => pair.first, "to" => pair.last)
          end
          seen << pair
        end
      end

      def validate_rules(attr, html_type)
        allowed = Array(ValidatorRegistry::HTML_TYPE_VALIDATORS[html_type])
        Array(attr["rules"]).each_with_index do |rule, index|
          type = rule["type"].to_s
          unless allowed.include?(type)
            add(
              attr_pointer(attr, "rules", index, "type"),
              "rule.not_allowed",
              "type" => type, "html_type" => html_type, "allowed" => allowed
            )
          end
          if type == "length_in_range" && rule["min"] && rule["max"] && rule["min"].to_f > rule["max"].to_f
            add(attr_pointer(attr, "rules", index), "rule.invalid_range", "min" => rule["min"], "max" => rule["max"])
          end
          if type == "format_custom" && rule["pattern"].present?
            begin
              Regexp.new(rule["pattern"].to_s)
            rescue RegexpError
              add(attr_pointer(attr, "rules", index, "pattern"), "rule.invalid_pattern", "pattern" => rule["pattern"])
            end
          end
        end
      end

      def validate_options(attr, html_type)
        options = attr["options"]
        return if options.blank?

        if options["source"].to_s == "static"
          values = Array(options["values"]).map { |value| option_stored_value(value) }.compact
          values.tally.each do |value, count|
            next if count < 2

            add(attr_pointer(attr, "options", "values"), "options.duplicate_values", "value" => value)
          end
        end

        unless SELECTION_TYPES.include?(html_type)
          add(attr_pointer(attr, "options"), "options.not_applicable", "html_type" => html_type)
          return
        end

        case options["source"].to_s
        when "static"
          # duplicates already reported above
        when "constant"
          name = options["constant"].to_s
          names = constant_names
          unless names.include?(name)
            candidates = Operations::Violation.candidates(name, names)
            add(
              attr_pointer(attr, "options", "constant"),
              "options.constant_not_found",
              { "name" => name, "candidates" => candidates },
              candidates.empty? ? "ask_user" : "fix_payload"
            )
          end
        when "entity_entries"
          target = options["entity"].to_s
          unless known_entity?(target)
            missing_entity(attr_pointer(attr, "options", "entity"), "options.entity_not_found", target)
          end
          validate_label_slug(attr_pointer(attr, "options", "label_field"), target, options["label_field"],
                              missing: "options.field_not_found", unlabelable: "options.label_field_not_labelable")
        end
      end

      def validate_file(attr, html_type)
        return if attr["file"].blank?
        return if FILE_TYPES.include?(html_type)

        add(attr_pointer(attr, "file"), "file.not_applicable", "html_type" => html_type)
      end

      def validate_formula(attr, kind, slugs)
        formula = attr["formula"]
        if formula.present? && kind != "calculated"
          add(attr_pointer(attr, "formula"), "formula.not_applicable", "kind" => kind)
          return
        end
        return if kind != "calculated" || formula.blank?

        references = formula_identifiers(formula)
        return if references.nil?

        own = attribute_slug(attr)
        references.each do |ident|
          next if ident == own || slugs.include?(ident)

          add(attr_pointer(attr, "formula"), "formula.unknown_reference", "name" => ident)
        end
      end

      def formula_identifiers(formula)
        tokens = FlowchartRuntime::FormulaCompiler.tokenize(formula.to_s)
        tokens.filter_map do |type, value|
          next unless type == :IDENT
          next if FORMULA_FUNCTIONS.include?(value.to_s.upcase)

          value.to_s
        end.uniq
      rescue StandardError
        nil
      end

      def validate_defaults
        defaults = (@spec.dig("settings", "default_values") || {})
        return unless defaults.is_a?(Hash)

        slugs = Array(@spec["attributes"]).map { |attr| attribute_slug(attr) }
        defaults.each_key do |key|
          next if slugs.include?(key.to_s)

          add(origin_or("settings", @spec["name"], "default_values", key), "settings.unknown_default_key", "key" => key)
        end
      end

      def validate_associations
        assocs = Array(@spec["associations"])
        names = assocs.map { |assoc| assoc["related_entity"].to_s }
        names.tally.each do |name, count|
          next if name.blank? || count < 2

          add(assoc_pointer(name, "related_entity"), "association.duplicate", "name" => name)
        end

        assocs.each do |assoc|
          target = assoc["related_entity"].to_s
          if target == @spec["name"].to_s
            add(assoc_pointer(target, "related_entity"), "association.self_reference", "name" => target)
          elsif !known_entity?(target)
            missing_entity(assoc_pointer(target, "related_entity"), "association.target_not_found", target)
          end

          validate_label_slug(assoc_pointer(target, "display_field"), target, assoc["display_field"],
                              missing: "association.display_field_not_found", unlabelable: "association.display_field_not_labelable")

          slugs = Array(assoc["bridge_attributes"]).map { |attr| attribute_slug(attr) }
          reserved = participant_slugs(@spec["name"], target)
          slugs.tally.each do |slug, count|
            next if slug.blank?

            if count > 1 || reserved.include?(slug) || RESERVED_SLUGS.include?(slug)
              add(bridge_pointer(target, slug, "slug"), "association.bridge_slug_conflict", "slug" => slug)
            end
          end
          Array(assoc["bridge_attributes"]).each do |attr|
            validate_attribute(attr, slugs, [])
          end
        end
      end

      def validate_owner_flags
        flagged = owner_flagged_attributes
        return if flagged.empty?

        if flagged.size > 1
          add(origin_or("details", @spec["name"]), "entity.owner_multiple", "name" => @spec["name"])
          return
        end

        attr, bridge = flagged.first
        return if owner_allowed?(attr, bridge: bridge)

        add(attr_pointer(attr, "owner"), "attribute.owner_invalid", "slug" => attribute_slug(attr))
      end

      def owner_flagged_attributes
        flagged = Array(@spec["attributes"]).filter_map do |attr|
          next unless attr["owner"] == true

          [attr, false]
        end
        Array(@spec["associations"]).each do |assoc|
          Array(assoc["bridge_attributes"]).each do |attr|
            next unless attr["owner"] == true

            flagged << [attr, true]
          end
        end
        flagged
      end

      def owner_allowed?(attr, bridge:)
        return false if bridge
        return false if person_spec?(@spec)
        return false unless public_reference?(attr)

        person_named?(attr.dig("options", "entity"))
      end

      def public_reference?(attr)
        attr.dig("options", "source").to_s == Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE
      end

      def person_spec?(spec)
        spec["extends"] == Capabilities::PERSON_MODEL
      end

      def person_named?(name)
        return false if name.blank?

        spec = @specs_by_name[name.to_s]
        return person_spec?(spec) if spec

        find_named_entity(name)&.person?
      end

      def find_named_entity(name)
        rows = Entity.unscope(where: :status).where(name: name, customer_id: [customer.id, nil]).to_a
        rows.find { |row| row.customer_id == customer.id } || rows.first
      end

      def validate_computed_aggregates
        Array(@spec["attributes"]).each do |attr|
          next unless (attr["kind"].presence || "input") == "computed"

          aggregate = stringify(attr["aggregate"])
          related = aggregate["related_entity"].to_s
          direction = (aggregate["direction"].presence || "source").to_s
          from, to = direction == "target" ? [related, @spec["name"].to_s] : [@spec["name"].to_s, related]
          unless association_between?(from, to)
            add(attr_pointer(attr, "aggregate", "related_entity"), "aggregate.association_missing", "entity" => related)
          end

          function = aggregate["function"].to_s
          source = aggregate["source_attribute"].to_s
          if function != "count" && source.blank?
            add(attr_pointer(attr, "aggregate", "source_attribute"), "aggregate.source_required", "function" => function)
          elsif source.present?
            bridge_attr = bridge_attribute(from, to, source)
            unless bridge_attr
              add(attr_pointer(attr, "aggregate", "source_attribute"), "aggregate.source_not_found", "slug" => source)
            end
            if bridge_attr && %w[avg sum min max].include?(function) &&
               NUMERIC_HTML_TYPES.exclude?(bridge_attr["html_type"].to_s)
              add(attr_pointer(attr, "aggregate", "source_attribute"), "aggregate.source_not_numeric", "slug" => source)
            end
          end

          filter = aggregate["filter"]
          next unless filter.is_a?(Hash)

          filter_slug = filter["attribute"].to_s
          next if filter_slug.blank? || bridge_attribute(from, to, filter_slug)

          add(attr_pointer(attr, "aggregate", "filter", "attribute"), "aggregate.filter_attribute_not_found", "slug" => filter_slug)
        end
      end

      def association_between?(from_name, to_name)
        spec = @specs_by_name[from_name]
        if spec
          return true if Array(spec["associations"]).any? { |assoc| assoc["related_entity"].to_s == to_name }
        end

        record = Entity.where(customer_id: customer.id).non_bridge.find_by(name: from_name)
        Array(record&.associations_list).any? { |assoc| assoc["target_entity_name"].to_s == to_name }
      end

      def bridge_attribute(from_name, to_name, slug)
        extras = bridge_attributes(from_name, to_name)
        extras.find { |attr| attribute_slug(attr) == slug }
      end

      def bridge_attributes(from_name, to_name)
        spec = @specs_by_name[from_name]
        if spec
          assoc = Array(spec["associations"]).find { |row| row["related_entity"].to_s == to_name }
          return Array(assoc&.[]("bridge_attributes"))
        end

        record = Entity.where(customer_id: customer.id).non_bridge.find_by(name: from_name)
        assoc = Array(record&.associations_list).find { |row| row["target_entity_name"].to_s == to_name }
        Array(assoc&.[]("additional_attributes")).map { |attr| mapper.attribute_from_stored(attr) }
      end

      def known_entity?(name)
        return false if name.blank?

        @known_names.include?(name)
      end

      def lookup_field?(entity_name, field)
        return true if SYSTEM_FIELDS.include?(field.to_s)

        slugs_for(entity_name).include?(field.to_s)
      end

      # A label or display field must be an attribute of the target that
      # Entities::ReferenceLabels can show; `id` never is. An unknown entity
      # is already reported where it is named.
      def validate_label_slug(pointer, entity_name, slug, missing:, unlabelable:)
        slug = slug.to_s
        return if slug.blank? || !known_entity?(entity_name)

        attribute = stored_attribute(entity_name, slug)
        if attribute.nil? && !SYSTEM_FIELDS.include?(slug)
          add(pointer, missing, "field" => slug, "entity" => entity_name)
        elsif !Entities::ReferenceLabels.labelable?(attribute)
          add(pointer, unlabelable, "field" => slug, "entity" => entity_name)
        end
      end

      # `slug` on `entity_name` in stored form, as this call leaves it: from a
      # spec in this call, else the catalog, else the record.
      def stored_attribute(entity_name, slug)
        spec = @specs_by_name[entity_name]
        if spec
          attr = Array(spec["attributes"]).find { |item| attribute_slug(item) == slug }
          return attr && mapper.attribute_to_stored(attr)
        end

        doc = @catalog[entity_name]
        schema = doc ? doc["property_schema"] : Entity.where(customer_id: customer.id).non_bridge.find_by(name: entity_name)&.property_schema_json
        Array(schema).find { |item| item.is_a?(Hash) && item["name_slug"].to_s == slug }
      end

      # update_entity: a display field that other entities or launched forms
      # rely on must stay labelable, and visible to those forms' audiences.
      # Mirrors EntitySchemaValidation#validate_referenced_display_fields.
      def guard_display_fields(spec, index)
        record = Entity.where(customer_id: customer.id).non_bridge.find_by(name: spec["name"].to_s)
        return unless record

        @entity_index = index
        @spec = spec
        dependents = Entities::ReferenceDependents.for_save(record)
        previous = Array(record.property_schema_json).grep(Hash).index_by { |attr| attr["name_slug"].to_s }
        current = Array(spec["attributes"]).to_h { |attr| [attribute_slug(attr), mapper.attribute_to_stored(attr)] }

        dependents.references.group_by(&:label_field).each do |slug, refs|
          next if slug.blank? || !Entities::ReferenceLabels.labelable?(previous[slug])
          next if Entities::ReferenceLabels.labelable?(current[slug])

          add(origin_or("attribute", slug), "attribute.display_field_in_use",
              "slug" => slug, "fields" => Entities::ReferenceDependents.field_paths(refs).to_sentence)
        end

        current.each do |slug, stored|
          next unless previous[slug]

          dependents.forms(slug).each do |form|
            audience = form.audiences.find do |aud|
              EntityAttributeAudience.visible_to?(previous[slug], aud) && !EntityAttributeAudience.visible_to?(stored, aud)
            end
            next unless audience

            add(origin_or("attribute", slug, "access"), "attribute.display_field_hidden",
                "slug" => slug, "audience" => audience, "form" => form.page.name)
          end
        end
      end

      def slugs_for(entity_name)
        spec = @specs_by_name[entity_name]
        return Array(spec["attributes"]).map { |attr| attribute_slug(attr) } if spec

        doc = @catalog[entity_name]
        if doc
          return Array(doc["property_schema"]).map { |attr| attr["name_slug"].to_s }
        end

        record = Entity.where(customer_id: customer.id).non_bridge.find_by(name: entity_name)
        Array(record&.property_schema_json).map { |attr| attr["name_slug"].to_s }
      end

      def constant_names
        @constant_names ||= Current.with_customer(customer) do
          Constant.where(customer_id: [customer.id, nil]).pluck(:name)
        end
      end

      def participant_slugs(source, target)
        [source, target].map { |name| EntityEntry.attribute_slug_for(name) }
      end

      def attribute_slug(attr)
        attr["slug"].presence || EntityEntry.attribute_slug_for(attr["name"])
      end

      def option_stored_value(value)
        case value
        when String then value.strip.presence
        when Hash
          value = stringify(value)
          value["value"].to_s.strip.presence || value["label"].to_s.strip.presence
        end
      end

      def spec_from_document(doc)
        doc = stringify(doc)
        {
          "name" => doc["name"],
          "display_label" => doc["display_label"],
          "description" => doc["description"],
          "extends" => doc["extended_model"],
          "settings" => {
            "icon" => doc["icon"],
            "color" => doc["color"],
            "default_values" => doc["default_properties"] || {}
          },
          "attribute_groups" => Array(doc["attribute_groups"]).map do |group|
            group = stringify(group)
            { "key" => group["id"], "name" => group["name"], "description" => group["description"],
              "icon" => group["icon"], "color" => group["color"] }.compact
          end,
          "attributes" => Array(doc["property_schema"]).map { |attr| mapper.attribute_from_stored(attr) },
          "associations" => Array(doc["associations"]).map do |assoc|
            assoc = stringify(assoc)
            {
              "related_entity" => assoc["associated_entity_name"],
              "display_field" => assoc["display_field"],
              "display_field_label" => assoc["display_field_label"],
              "bridge_attributes" => Array(assoc["additional_attributes"]).map { |attr| mapper.attribute_from_stored(attr) }
            }
          end
        }
      end

      def attr_pointer(attr, *rest)
        slug = attribute_slug(attr)
        origin_or("attribute", slug, *rest)
      end

      def assoc_pointer(name, *rest)
        origin_or("association", name, *rest)
      end

      def bridge_pointer(related, slug, *rest)
        origin_or("bridge", "#{related}:#{slug}", *rest)
      end

      def origin_or(kind, id, *rest)
        origin = @origins[@entity_index]&.[]("#{kind}:#{id}")
        if origin
          Operations::Pointer.join(origin, *rest)
        elsif @mode == :create
          path_for_create(kind, id, rest)
        else
          Operations::Pointer.join(@pointer_base, @entity_index, *rest)
        end
      end

      def path_for_create(kind, id, rest)
        case kind
        when "attribute"
          index = Array(@spec["attributes"]).index { |attr| attribute_slug(attr) == id }
          return Operations::Pointer.join(@pointer_base, @entity_index, "attributes", index, *rest) if index

          Array(@spec["associations"]).each_with_index do |assoc, assoc_index|
            bridge_index = Array(assoc["bridge_attributes"]).index { |attr| attribute_slug(attr) == id }
            next unless bridge_index

            return Operations::Pointer.join(
              @pointer_base, @entity_index, "associations", assoc_index, "bridge_attributes", bridge_index, *rest
            )
          end
          Operations::Pointer.join(@pointer_base, @entity_index, "attributes", *rest)
        when "group"
          index = Array(@spec["attribute_groups"]).index { |group| group["key"].to_s == id }
          Operations::Pointer.join(@pointer_base, @entity_index, "attribute_groups", index, *rest)
        when "association"
          index = Array(@spec["associations"]).index { |assoc| assoc["related_entity"].to_s == id }
          Operations::Pointer.join(@pointer_base, @entity_index, "associations", index, *rest)
        when "settings"
          Operations::Pointer.join(@pointer_base, @entity_index, "settings", *rest)
        else
          Operations::Pointer.join(@pointer_base, @entity_index, *rest)
        end
      end

      def missing_entity(pointer, code, name)
        candidates = Operations::Violation.candidates(name, @known_names)
        add(pointer, code, { "name" => name, "candidates" => candidates },
            candidates.empty? ? "ask_user" : "fix_payload")
      end

      def add(pointer, code, details = {}, resolution = nil)
        @violations << Operations::Violation.new(
          pointer: pointer.to_s,
          code: code,
          details: details,
          resolution: resolution
        )
      end

      def stringify(value)
        MergePatch.stringify(value)
      end
    end
  end
end
