# frozen_string_literal: true

module EntityDefinitions
  module Assistant
    # What a proposed document would actually do to entities that already
    # exist — the diff the admin reviews before anything is written.
    #
    # The plan is computed by DOING the write, not by describing it: the
    # document is applied to an unsaved copy of the record through the same
    # DefinitionAssignment the writer uses, and the two definition snapshots
    # are compared. "Nothing to review" therefore means "the merge changes
    # nothing", by construction. The previous version compared an allowlist of
    # keys, and every key nobody thought to enumerate — a dropped association,
    # an overwritten display label, a choice list's label_field — was a change
    # that applied without anyone seeing it.
    #
    # Only machine values are produced: field names, before/after values,
    # severity. The plan is stored in the assistant message's metadata and
    # rendered later, possibly in another locale, so every word the admin
    # reads is chosen by the ViewComponent. Nothing here is pre-formatted or
    # pre-joined, because a string cannot be translated once it is in the
    # database.
    #
    # An entity the document would leave untouched produces NO entry. The
    # model is fed the entity catalog and routinely echoes a definition back
    # verbatim; treating that echo as a change would ask for a confirmation
    # that changes nothing, and the loop would never converge.
    #
    # Creates are not part of the plan: an entity that does not exist yet has
    # nothing to review and is written straight away.
    class ChangePlan
      include DefinitionAssignment

      # Raised by #fail! when the document cannot even be applied in memory.
      # It never opens the gate — see #entry_for.
      Unplannable = Class.new(StandardError)

      # Stands in for an entity the document references but that does not
      # exist yet, so planning a document that creates Course and points
      # Student at it resolves instead of collapsing into "cannot plan".
      # It is never written; only its name reaches the diff.
      PendingTarget = Struct.new(:id, :name)

      # Snapshot keys that are collections with their own matching rules.
      STRUCTURED_KEYS = %w[property_schema attribute_groups associations default_properties].freeze

      # Keys whose change re-homes or re-bases stored entries.
      BREAKING_IDENTITY_KEYS = %w[extended_model].freeze

      # Attribute keys whose change reinterprets values already stored under
      # that slug: a new control parses the value differently, and a new
      # `type` turns a stored input field into a derived read-only one.
      BREAKING_ATTRIBUTE_KEYS = %w[html_type type].freeze

      # Attribute keys the generic walk must not treat as scalars.
      ATTRIBUTE_SPECIAL_KEYS = %w[config validators group_id].freeze

      # Payload caps. `removed` options are drawn from what is stored rather
      # than from what the model authored, so even a short document can
      # describe a very long change.
      OPTION_LIMIT = 20
      ROW_LIMIT = 50

      # config keys that describe WHICH list an attribute reads. They are
      # compared as one through ChoiceList.source_of, which is the only thing
      # that knows the stored `entity_id` and the exchanged
      # `options_entity_name` are the same binding.
      SOURCE_CONFIG_KEYS = %w[options options_source options_entity_name entity_id].freeze

      # Derived from the binding by the write, so a rebind already accounts
      # for them.
      BINDING_CONFIG_KEYS = %w[label_field].freeze

      # Identity columns that are part of the definition but not of the
      # version snapshot.
      RECORD_IDENTITY_KEYS = %w[display_label extended_model].freeze

      # Attribute-row fields that are not schema keys: the choice list is
      # compared as a list and as a binding, and `config` carries the rest of
      # the config under its own `config_key`.
      SYNTHETIC_ATTRIBUTE_KEYS = %w[validators options options_source config].freeze

      Plan = Struct.new(:entries, keyword_init: true) do
        def changed_names = entries.map { |entry| entry["name"] }

        def breaking_names = entries.select { |entry| entry["breaking"] }.map { |entry| entry["name"] }

        def any? = entries.any?

        def as_json(*) = entries.map(&:deep_stringify_keys)
      end

      def self.call(entities:, customer:, replace: false)
        new(entities: entities, customer: customer, replace: replace).call
      end

      # What a `kind: "identity"` row's `field` can be. The diff does not read
      # this — it walks whatever the two snapshots hold — but the component
      # needs wording ready for each one, so it is derived from the snapshot
      # itself rather than typed out a second time.
      def self.identity_fields
        (Entity.new.definition_snapshot.keys - STRUCTURED_KEYS) | RECORD_IDENTITY_KEYS
      end

      # What a `kind: "attribute"` row's `field` can be: every key the schema
      # lets an attribute carry, plus the synthetic ones. Same contract as
      # above — a declaration for the renderer, not a filter for the diff.
      def self.attribute_fields
        (Normalizer::ATTRIBUTE_KEYS - ATTRIBUTE_SPECIAL_KEYS) | SYNTHETIC_ATTRIBUTE_KEYS | %w[group_id]
      end

      # Normalized first, because that is what Persist writes: the normalizer
      # drops keys the contract does not allow, canonicalizes a choice list,
      # renames target_entity_name, and defaults a missing html_type to text.
      # Planning the raw document would mean planning something other than
      # the thing that gets written.
      def initialize(entities:, customer:, replace: false)
        @entities = Normalizer.call(Array(entities).grep(Hash)).definitions
        @customer = customer
        @replace = replace
        @resolved = {}
      end

      def call
        Plan.new(entries: entries)
      end

      private

      def entries
        existing_records.filter_map { |name, record| entry_for(record, proposals.fetch(name)) }
      end

      # A document that cannot be applied in memory is reported as changed,
      # never as unchanged: the gate must not open because the plan failed.
      # It is close to unreachable — the operation's schema and semantic
      # validation run first and unknown association targets resolve to a
      # PendingTarget — and everything left
      # (an invented extended_model, say) is a document Persist would refuse
      # anyway, so the admin meets an error rather than a silent write.
      def entry_for(record, definition)
        before = snapshot(record)
        after = simulate(record, definition)
        rows = rows_for(before, after)
        return nil if rows.empty?

        # Severity is read from the whole diff, before the cap drops anything:
        # an entry must not look safe because its breaking row was the
        # fifty-first.
        entry(record, breaking: rows.any? { |row| row["breaking"] }, rows: rows)
      rescue Unplannable => e
        Rails.logger.warn("[entity_definitions.change_plan] #{record.name} cannot be planned: #{e.message}")
        entry(record, breaking: true, rows: []).merge("unplannable" => true)
      end

      def entry(record, breaking:, rows:)
        kept, omitted = capped_rows(rows)
        {
          "name" => record.name,
          "id" => record.id,
          "breaking" => breaking,
          "rows" => kept,
          "omitted_rows" => omitted
        }
      end

      # This payload is stored in ai_assistant_messages.metadata and rendered
      # as chips in one chat bubble, so its size is bounded here rather than
      # by how much the model chose to send: a 60-field relabel of 40 options
      # each measured 522 KB and roughly 2400 chips. The overflow is reported
      # as a count for the panel to word.
      #
      # When the cap bites, breaking rows are kept first — which fifty rows
      # survive is arbitrary, but showing the destructive ones is not.
      def capped_rows(rows)
        return [rows, 0] if rows.size <= ROW_LIMIT

        breaking, rest = rows.partition { |row| row["breaking"] }
        kept = (breaking + rest).first(ROW_LIMIT)
        [kept, rows.size - kept.size]
      end

      # Proposed definitions keyed by the name that identifies them. One
      # definition per name is safe to assume: update_entity rejects a
      # request that names an entity twice before it is planned, and
      # Normalizer drops both copies at the door of the write. Folding several
      # definitions onto one copy here would be a second merge semantics to
      # keep in step with Persist forever.
      def proposals
        @proposals ||= @entities.index_by { |row| row["name"].to_s.strip }.except("")
      end

      # Deliberately the default `visible` scope, while Persist looks the same
      # name up with `unscope(where: :status)`. A trashed entity therefore
      # plans as nothing, passes the gate, and is then refused outright by
      # Persist ("cannot update inactive entity") with nothing written. The
      # asymmetry is safe in that direction only: widening this lookup to
      # include trashed rows would let one be written after a review of a
      # record the admin cannot even see.
      def existing_records
        return {} if proposals.empty? || @customer.blank?

        # Deliberately not `includes(current_version: :content)`: Entity reads
        # its definition back from the head version in an after_find, which
        # runs while each record is still being instantiated, so no preloader
        # or join has been applied yet. Measured on 20 entities, a plain load,
        # `includes` and `eager_load` all cost the same 41 queries — the two
        # per record are the model's hydration, not something this query can
        # batch. Making them batchable means changing how Versionable
        # hydrates, which is every read path in the app, not this one.
        @existing_records ||= Entity.where(customer_id: @customer.id, name: proposals.keys)
                                    .non_bridge
                                    .index_by(&:name)
                                    .slice(*proposals.keys)
                                    .each { |name, record| @resolved[name] = record }
      end

      # ----------------------------------------------------------------------
      # Applying the document to a copy
      # ----------------------------------------------------------------------

      def tenant_id = @customer.id

      def fail!(messages)
        raise Unplannable, Array(messages).join(" ")
      end

      # Whether the tenant may extend that base model is the write's decision.
      # Reporting the row the document asks for tells the admin more than
      # "this cannot be planned", and the write still refuses it.
      def validate_extended_model!(_class_name) = nil

      # One query per distinct name, memoized across the whole plan — this
      # runs on every persistable turn.
      def resolve_entity(name)
        return nil if name.blank?

        @resolved.fetch(name) do
          @resolved[name] = Entity.where(customer_id: tenant_id).non_bridge.find_by(name: name) ||
                            PendingTarget.new(nil, name)
        end
      end

      # The definition body plus the identity columns that live outside it.
      # Entity#definition_snapshot is the same hash the writer versions, so
      # anything Persist can write is in here whether or not this class knows
      # what it means.
      def snapshot(record)
        record.definition_snapshot.merge(
          "display_label" => record.display_label,
          "extended_model" => record.extended_model
        )
      end

      # The write, on a copy, without the write. #dup gives an unsaved record
      # that shares nothing the assignment mutates in place, and nothing here
      # saves or calls sync_bridge_entities! (which does).
      def simulate(record, definition)
        copy = record.dup
        # #dup clears the id, and the id is what says "this association points
        # at the entity it is defined on". Restored so a Student -> Student
        # association is caught here exactly as the write catches it. Nothing
        # in this method saves, so the copy never becomes a row.
        copy.id = record.id
        assign_identity(copy, definition, record.name)
        body = assign_body(copy, definition, replace: @replace)
        assign_associations(copy, record, definition)
        assign_computed(copy, body)
        snapshot(copy)
      end

      def assign_associations(copy, record, definition)
        return unless definition.key?("associations")

        copy.associations_json = carry_bridges(
          record.associations_list,
          stored_associations(copy, definition["associations"])
        )
      end

      # Computed attributes are held back by the assignment and resolved
      # against the bridge in a second pass. When the bridge does not exist
      # yet — a relationship this same document is introducing — the authored
      # field is merged unresolved, so the attribute still appears in the plan
      # instead of vanishing from it.
      def assign_computed(copy, body)
        return if body.computed_attributes.blank?

        resolved = begin
          body.computed_attributes.map { |field| resolve_computed(copy, field) }
        rescue Unplannable
          body.computed_attributes
        end
        copy.property_schema_json = if @replace
          reinsert_computed(copy.property_schema_json, resolved, body.computed_slots)
        else
          merge_attributes(copy.property_schema_json, resolved)
        end
        apply_grouping!(copy, body.incoming_groups, replace: @replace)
      end

      # ----------------------------------------------------------------------
      # Diffing the two snapshots
      # ----------------------------------------------------------------------

      def rows_for(before, after)
        identity_rows(before, after) +
          attribute_rows(before, after) +
          group_rows(before, after) +
          association_rows(before, after) +
          default_properties_rows(before, after)
      end

      # Every top-level field either snapshot carries, so a key added to the
      # definition shows up here the day it is written rather than the day
      # somebody remembers to list it.
      def identity_rows(before, after)
        (before.keys | after.keys).filter_map do |field|
          next if STRUCTURED_KEYS.include?(field)

          previous = comparable(before[field])
          current = comparable(after[field])
          next if previous == current

          {
            "kind" => "identity",
            "action" => "modified",
            "field" => field,
            "before" => previous,
            "after" => current,
            "breaking" => BREAKING_IDENTITY_KEYS.include?(field)
          }
        end
      end

      # The sections on each side of the change, so an attribute's group_id
      # can be reported as the name the admin gave that section.
      Sections = Struct.new(:before, :after, keyword_init: true)

      def attribute_rows(before, after)
        stored = attributes_by_key(before)
        incoming = attributes_by_key(after)
        sections = Sections.new(before: groups_by_id(before), after: groups_by_id(after))
        (stored.keys | incoming.keys).flat_map do |key|
          previous = stored[key]
          current = incoming[key]
          next [removed_attribute_row(previous)] if current.nil? && @replace
          next [] if current.nil?
          next [added_attribute_row(current)] if previous.nil?

          modified_attribute_rows(previous, current, sections)
        end
      end

      # Matched the way the merge matches them, so "changed" and "merged onto"
      # can never disagree. A keyless attribute is dropped: it cannot be
      # matched or merged, so it carries nothing to review. The schema
      # requires `name`, so such a document never reaches the gate.
      def attributes_by_key(snapshot)
        Array(snapshot["property_schema"]).grep(Hash)
                                          .index_by { |attr| attribute_key(attr) }
                                          .except("")
      end

      def added_attribute_row(attr)
        {
          "kind" => "attribute",
          "action" => "added",
          "name" => attribute_name(attr, nil),
          "html_type" => attr["html_type"].to_s,
          "breaking" => false
        }
      end

      def removed_attribute_row(attr)
        {
          "kind" => "attribute_removed",
          "action" => "removed",
          "name" => attribute_name(attr, nil),
          "breaking" => true
        }
      end

      def modified_attribute_rows(previous, current, sections)
        name = attribute_name(current, previous)
        fields = previous.keys | current.keys
        rows = fields.filter_map do |field|
          next if ATTRIBUTE_SPECIAL_KEYS.include?(field)

          scalar_attribute_row(name, field, previous[field], current[field])
        end
        rows.concat(validator_rows(name, previous, current)) if fields.include?("validators")
        rows.concat(group_id_rows(name, previous, current, sections)) if fields.include?("group_id")
        rows.concat(config_rows(name, previous, current)) if fields.include?("config")
        rows
      end

      def scalar_attribute_row(name, field, previous, current)
        previous = comparable(previous)
        current = comparable(current)
        return nil if previous == current

        attribute_row(name, field).merge(
          "before" => previous,
          "after" => current,
          "breaking" => BREAKING_ATTRIBUTE_KEYS.include?(field)
        )
      end

      # Validators travel as their registry type keys, which the component
      # translates at render time; a joined sentence here could only ever be
      # in one language. The list is compared whole — a bound moving from 32
      # to 64 is a change — but shown as its types, which is what a reader of
      # the panel can act on.
      def validator_rows(name, previous, current)
        return [] if canonical_validators(previous["validators"]) == canonical_validators(current["validators"])

        [attribute_row(name, "validators").merge(
          "before" => validator_types(previous["validators"]),
          "after" => validator_types(current["validators"]),
          "breaking" => false
        )]
      end

      def validator_types(validators)
        Array(validators).filter_map do |validator|
          value = validator.is_a?(Hash) ? validator["type"] : validator
          value.to_s.strip.presence
        end.sort
      end

      # A validator list is a set, not an ordering, and a bare type is the
      # same rule as its object form — both are how the schema lets one be
      # written. Compared as type plus parameters, so a reordered or
      # reshaped echo is not a change while a moved bound still is.
      def canonical_validators(validators)
        Array(validators).filter_map do |validator|
          validator = { "type" => validator } unless validator.is_a?(Hash)
          type = validator["type"].to_s.strip
          next if type.blank?

          { "type" => type, "config" => canonical(validator["config"]) }
        end.sort_by { |validator| validator["type"] }
      end

      # A group id is an internal handle; the section's name is what the admin
      # gave it. The raw id is only shown when it names nothing.
      def group_id_rows(name, previous, current, sections)
        was = group_name(sections.before, previous["group_id"])
        now = group_name(sections.after, current["group_id"])
        return [] if was == now

        [attribute_row(name, "group_id").merge("before" => was, "after" => now, "breaking" => false)]
      end

      def group_name(groups, group_id)
        id = group_id.to_s.strip
        return nil if id.blank?

        group = groups[id]
        group ? group["name"].to_s.strip.presence || id : id
      end

      def config_rows(name, previous, current)
        previous_config = predicted_config(config_of(previous))
        current_config = predicted_config(config_of(current))
        was = source_of(previous_config)
        now = source_of(current_config)
        return rebound_rows(name, previous_config, current_config, was, now) if was != now

        rows = now.nil? ? option_rows(name, previous_config, current_config) : []
        rows + config_key_rows(name, previous_config, current_config)
      end

      # A rebind reports the move, not the move's consequences. The static
      # list the attribute leaves behind is a consequence of the rebind, which
      # is why no options row is emitted here either.
      def rebound_rows(name, previous, current, was, now)
        row = attribute_row(name, "options_source").merge(
          "before" => source_value(was), "after" => source_value(now), "breaking" => true
        )
        [row] + config_key_rows(name, previous, current, except: BINDING_CONFIG_KEYS)
      end

      # Everything in the config that is not the choice list itself: a
      # Computed field's precision or filter, a bound list's label_field. The
      # merge replaces the whole config, so these move whether or not anyone
      # enumerated them.
      def config_key_rows(name, previous, current, except: [])
        ((previous.keys | current.keys) - SOURCE_CONFIG_KEYS - except).filter_map do |key|
          was = comparable(previous[key])
          now = comparable(current[key])
          next if was == now

          attribute_row(name, "config").merge(
            "config_key" => key, "before" => was, "after" => now, "breaking" => false
          )
        end
      end

      # Adding options to a list is additive, but pointing the list somewhere
      # else is not: values already stored under that slug came from the old
      # list and may not exist in the new one. Covers static <-> entity-bound
      # in both directions and a different source entity. A faithful echo of
      # the current binding compares equal.
      def source_of(config)
        ChoiceList.source_of(config, names_by_id: entity_names)
      end

      # Structured, not a sentence: the component decides how to word "reads
      # its own list" versus "reads Product entries".
      def source_value(source)
        return { "kind" => "static" } if source.nil?

        { "kind" => "entity", "entity_name" => source.entity_name }
      end

      def config_of(attribute)
        config = attribute["config"]
        config.is_a?(Hash) ? config.stringify_keys : {}
      end

      # What the write will store for a list bound to another entity's
      # entries. The write adds options_source and resolves the name to an id.
      def predicted_config(config)
        return config if config[ChoiceList::ENTITY_NAME_KEY].blank?

        config.merge("options_source" => Capabilities::ENTITY_ENTRIES_OPTIONS_SOURCE)
      end

      def entity_names
        @entity_names ||= @customer ? ChoiceList.names_by_id(@customer.id) : {}
      end

      # The merge replaces an attribute's config wholesale, so an option the
      # document leaves out is an option that disappears. A relabelled option
      # keeps its stored value and changes no entry, but it does change what
      # the admin reads on the form.
      def option_rows(name, previous, current)
        was = canonical_options(previous)
        now = canonical_options(current)
        added = now.reject { |value, _label| was.key?(value) }.values
        removed = was.reject { |value, _label| now.key?(value) }.values
        relabelled = relabelled_options(was, now)
        return [] if added.empty? && removed.empty? && relabelled.empty?

        buckets = [added, removed, relabelled].map { |bucket| bucket.first(OPTION_LIMIT) }
        [attribute_row(name, "options").merge(
          "added" => buckets[0],
          "removed" => buckets[1],
          "relabelled" => buckets[2],
          "omitted" => (added.size + removed.size + relabelled.size) - buckets.sum(&:size),
          "breaking" => false
        )]
      end

      def relabelled_options(before, after)
        after.filter_map do |value, label|
          previous = before[value]
          next if previous.nil? || previous == label

          { "before" => previous, "after" => label }
        end
      end

      # value => label, canonicalized the way Normalizer canonicalizes a list
      # on the way in, so a bare string and its {value,label} form are one
      # option.
      def canonical_options(config)
        Array(config["options"]).filter_map { |option| canonical_option(option) }.to_h
      end

      def canonical_option(option)
        case option
        when String
          option.strip.presence&.then { |value| [value, value] }
        when Hash
          option = option.stringify_keys
          option_pair(option["value"].to_s.strip, option["label"].to_s.strip)
        end
      end

      def option_pair(value, label)
        return nil if value.blank? && label.blank?

        [value.presence || label, label.presence || value]
      end

      def attribute_row(name, field)
        { "kind" => "attribute", "action" => "modified", "name" => name, "field" => field }
      end

      def attribute_name(current, previous)
        current["name"].to_s.strip.presence ||
          previous&.dig("name").to_s.strip.presence ||
          current["display_label"].to_s.strip.presence ||
          attribute_key(current)
      end

      # ----------------------------------------------------------------------
      # Groups, associations, defaults
      # ----------------------------------------------------------------------

      # Coarse on purpose: a group is a container, and which of its labels
      # moved matters far less to the reviewer than that the sections changed.
      def group_rows(before, after)
        was = groups_by_id(before)
        now = groups_by_id(after)
        (was.keys | now.keys).filter_map do |id|
          previous = was[id]
          current = now[id]
          next group_row("added", current) if previous.nil?
          next group_row("removed", previous) if current.nil?
          next if comparable(previous) == comparable(current)

          group_row("modified", current)
        end
      end

      def groups_by_id(snapshot)
        Array(snapshot["attribute_groups"]).grep(Hash).index_by { |group| group["id"].to_s }
      end

      def group_row(action, group)
        {
          "kind" => "group",
          "action" => action,
          "name" => group["name"].to_s.strip,
          "breaking" => false
        }
      end

      # The assignment replaces the association list wholesale and the write
      # then soft-deletes the bridge of anything no longer listed, taking the
      # link data with it. A dropped association is the most destructive thing
      # in a document, so it is breaking.
      def association_rows(before, after)
        was = associations_by_name(before)
        now = associations_by_name(after)
        (was.keys | now.keys).filter_map do |target|
          previous = was[target]
          current = now[target]
          next association_row("added", target, breaking: false) if previous.nil?
          next association_row("removed", target, breaking: true) if current.nil?
          next if comparable(previous) == comparable(current)

          association_row("modified", target, breaking: false)
        end
      end

      def associations_by_name(snapshot)
        Array(snapshot["associations"]).grep(Hash)
                                       .index_by { |assoc| assoc["target_entity_name"].to_s.strip }
                                       .except("")
      end

      def association_row(action, name, breaking:)
        { "kind" => "association", "action" => action, "name" => name, "breaking" => breaking }
      end

      def default_properties_rows(before, after)
        return [] if comparable(before["default_properties"]) == comparable(after["default_properties"])

        [{ "kind" => "default_properties", "action" => "modified", "breaking" => false }]
      end

      # ----------------------------------------------------------------------

      # Hash keys sorted at every depth, because key order carries no meaning
      # in any of these payloads and a reordered echo must not read as a
      # change. Array order is left alone — it is display order everywhere
      # this app stores one.
      def canonical(value)
        case value
        when Hash then value.stringify_keys.sort.to_h { |key, nested| [key, canonical(nested)] }
        when Array then value.map { |nested| canonical(nested) }
        else value
        end
      end

      # Comparison and display in one step: nil, "" and "   " all mean "no
      # value", and everything else keeps its own type so the component
      # receives a machine value rather than a rendering of one.
      def comparable(value)
        value = canonical(value)
        value.is_a?(String) ? value.strip.presence : value
      end
    end
  end
end
