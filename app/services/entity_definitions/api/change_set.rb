# frozen_string_literal: true

module EntityDefinitions
  module Api
    # Applies update_entity change ops to a Catalog stored-shape document.
    # Untouched attributes stay byte-identical. Violations carry the change pointer.
    class ChangeSet
      Result = Struct.new(:document, :violations, :origins, keyword_init: true) do
        def ok? = violations.empty?
      end

      def self.apply(document, changes, mapper:, pointer_prefix:)
        new(document, changes, mapper: mapper, pointer_prefix: pointer_prefix).apply
      end

      def initialize(document, changes, mapper:, pointer_prefix:)
        @document = deep_copy(document)
        @changes = Array(changes)
        @mapper = mapper
        @pointer_prefix = pointer_prefix
        @violations = []
        @origins = {}
      end

      def apply
        @changes.each_with_index { |change, index| apply_change(stringify(change), index) }
        Result.new(document: @document, violations: @violations, origins: @origins)
      end

      private

      attr_reader :mapper

      def apply_change(change, index)
        @index = index
        @change = change
        case change["op"].to_s
        when "set_details" then set_details
        when "set_settings" then set_settings
        when "add_attribute" then add_attribute
        when "update_attribute" then update_attribute
        when "remove_attribute" then remove_attribute
        when "move_attribute" then move_attribute
        when "add_group" then add_group
        when "update_group" then update_group
        when "remove_group" then remove_group
        when "reorder_groups" then reorder_groups
        when "add_association" then add_association
        when "update_association" then update_association
        when "remove_association" then remove_association
        when "add_bridge_attribute" then add_bridge_attribute
        when "update_bridge_attribute" then update_bridge_attribute
        when "remove_bridge_attribute" then remove_bridge_attribute
        end
      end

      def set_details
        remember("details", @document["name"], pointer)
        @document["display_label"] = @change["display_label"] if @change.key?("display_label")
        @document["description"] = @change["description"] if @change.key?("description")
        @document["extended_model"] = @change["extends"] if @change.key?("extends")
      end

      def set_settings
        remember("settings", @document["name"], pointer)
        @document["icon"] = @change["icon"] if @change.key?("icon")
        @document["color"] = @change["color"] if @change.key?("color")
        @document["default_properties"] = stringify(@change["default_values"]) if @change.key?("default_values")
      end

      def add_attribute
        stored = mapper.attribute_to_stored(@change["attribute"])
        slug = stored["name_slug"].to_s
        remember("attribute", slug, join("attribute"))
        inserted = insert_into(attributes, stored, @change["position"], &:name_slug)
        return unless inserted

        @document["property_schema"] = inserted
      end

      def update_attribute
        slug = @change["slug"].to_s
        remember("attribute", slug, join("set"))
        index = find_attr_index(slug)
        return missing_attribute(slug) unless index

        stored = attributes[index]
        public = mapper.attribute_from_stored(stored)
        patched = MergePatch.apply(public, @change["set"])
        patched["slug"] = stored["name_slug"]
        drop_inapplicable_fields!(patched)
        attributes[index] = mapper.attribute_to_stored(patched, base: stored)
      end

      def remove_attribute
        slug = @change["slug"].to_s
        remember("attribute", slug, join("slug"))
        index = find_attr_index(slug)
        return missing_attribute(slug) unless index

        if attribute_in_use?(slug)
          add_violation(join("slug"), "attribute.in_use", "slug" => slug)
          return
        end

        attributes.delete_at(index)
        defaults = stringify(@document["default_properties"] || {})
        defaults.delete(slug)
        @document["default_properties"] = defaults
      end

      def move_attribute
        slug = @change["slug"].to_s
        remember("attribute", slug, pointer)
        index = find_attr_index(slug)
        return missing_attribute(slug) unless index

        if @change.key?("to_group")
          dest = @change["to_group"]
          if dest.present? && find_group_index(dest).nil?
            missing_group(dest, join("to_group"))
            return
          end
          if dest.present?
            attributes[index]["group_id"] = dest
          else
            attributes[index].delete("group_id")
          end
        end

        return unless @change.key?("position")

        item = attributes.delete_at(index)
        inserted = insert_into(attributes, item, @change["position"], &:name_slug)
        @document["property_schema"] = inserted if inserted
      end

      def add_group
        stored = group_to_stored(@change["group"])
        key = stored["id"].to_s
        remember("group", key, join("group"))
        inserted = insert_into(groups, stored, @change["position"], &:id)
        return unless inserted

        @document["attribute_groups"] = inserted
        Array(@change["attributes"]).each do |attr|
          public = stringify(attr).merge("group" => key)
          stored_attr = mapper.attribute_to_stored(public)
          remember("attribute", stored_attr["name_slug"].to_s, join("attributes"))
          attributes << stored_attr
        end
      end

      def update_group
        key = @change["key"].to_s
        remember("group", key, join("set"))
        index = find_group_index(key)
        return missing_group(key, join("key")) unless index

        stored = groups[index]
        public = group_from_stored(stored)
        patched = MergePatch.apply(public, @change["set"])
        patched["key"] = stored["id"]
        groups[index] = group_to_stored(patched)
      end

      def remove_group
        key = @change["key"].to_s
        remember("group", key, join("key"))
        index = find_group_index(key)
        return missing_group(key, join("key")) unless index

        dest = @change["move_attributes_to"]
        if dest.present?
          if dest.to_s == key || find_group_index(dest).nil?
            missing_group(dest, join("move_attributes_to"))
            return
          end
          attributes.each { |attr| attr["group_id"] = dest if attr["group_id"].to_s == key }
        else
          attributes.each { |attr| attr.delete("group_id") if attr["group_id"].to_s == key }
        end
        groups.delete_at(index)
      end

      def reorder_groups
        order = Array(@change["order"]).map(&:to_s)
        current = groups.map { |group| group["id"].to_s }
        if order.sort != current.sort
          add_violation(join("order"), "group.order_mismatch", "expected" => current.join(", "))
          return
        end

        by_id = groups.index_by { |group| group["id"].to_s }
        @document["attribute_groups"] = order.map { |id| by_id[id] }
        remember("groups", @document["name"], join("order"))
      end

      def add_association
        stored = association_to_stored(@change["association"])
        name = stored["associated_entity_name"].to_s
        remember("association", name, join("association"))
        associations << stored
      end

      def update_association
        name = @change["related_entity"].to_s
        remember("association", name, join("set"))
        index = find_assoc_index(name)
        return missing_association(name) unless index

        stored = associations[index]
        patch = stringify(@change["set"])
        stored["display_field"] = patch["display_field"] if patch.key?("display_field")
        stored["display_field_label"] = patch["display_field_label"] if patch.key?("display_field_label")
        if patch.key?("bridge_attributes")
          stored["additional_attributes"] = Array(patch["bridge_attributes"]).map do |attr|
            mapper.attribute_to_stored(attr)
          end
        end
      end

      def remove_association
        name = @change["related_entity"].to_s
        remember("association", name, join("related_entity"))
        index = find_assoc_index(name)
        return missing_association(name) unless index

        associations.delete_at(index)
      end

      def add_bridge_attribute
        name = @change["related_entity"].to_s
        index = find_assoc_index(name)
        return missing_association(name) unless index

        stored = mapper.attribute_to_stored(@change["attribute"])
        slug = stored["name_slug"].to_s
        remember("bridge", "#{name}:#{slug}", join("attribute"))
        extras = extras_of(associations[index])
        inserted = insert_into(extras, stored, @change["position"], &:name_slug)
        return unless inserted

        associations[index]["additional_attributes"] = inserted
      end

      def update_bridge_attribute
        name = @change["related_entity"].to_s
        slug = @change["slug"].to_s
        remember("bridge", "#{name}:#{slug}", join("set"))
        assoc_index = find_assoc_index(name)
        return missing_association(name) unless assoc_index

        extras = extras_of(associations[assoc_index])
        attr_index = extras.index { |attr| attr["name_slug"].to_s == slug }
        return missing_attribute(slug, dictionary: extras.map { |attr| attr["name_slug"].to_s }) unless attr_index

        stored = extras[attr_index]
        public = mapper.attribute_from_stored(stored)
        patched = MergePatch.apply(public, @change["set"])
        patched["slug"] = stored["name_slug"]
        drop_inapplicable_fields!(patched)
        extras[attr_index] = mapper.attribute_to_stored(patched, base: stored)
        associations[assoc_index]["additional_attributes"] = extras
      end

      def remove_bridge_attribute
        name = @change["related_entity"].to_s
        slug = @change["slug"].to_s
        remember("bridge", "#{name}:#{slug}", join("slug"))
        assoc_index = find_assoc_index(name)
        return missing_association(name) unless assoc_index

        extras = extras_of(associations[assoc_index])
        attr_index = extras.index { |attr| attr["name_slug"].to_s == slug }
        return missing_attribute(slug, dictionary: extras.map { |attr| attr["name_slug"].to_s }) unless attr_index

        if bridge_attribute_in_use?(name, slug)
          add_violation(join("slug"), "attribute.in_use", "slug" => slug)
          return
        end

        extras.delete_at(attr_index)
        associations[assoc_index]["additional_attributes"] = extras
      end

      def attributes
        @document["property_schema"] ||= []
      end

      def groups
        @document["attribute_groups"] ||= []
      end

      def associations
        @document["associations"] ||= []
      end

      def extras_of(assoc)
        Array(assoc["additional_attributes"])
      end

      def find_attr_index(slug)
        attributes.index { |attr| attr["name_slug"].to_s == slug }
      end

      def find_group_index(key)
        groups.index { |group| group["id"].to_s == key.to_s }
      end

      def find_assoc_index(name)
        associations.index { |assoc| assoc["associated_entity_name"].to_s == name }
      end

      def insert_into(list, item, position, &id_of)
        return list + [item] if position.blank?

        position = stringify(position)
        target = (position["before"] || position["after"]).to_s
        index = list.index { |entry| id_of.call(Ident.new(entry)) == target }
        unless index
          add_violation(join("position"), "change.position_target_not_found", "target" => target)
          return nil
        end

        insert_at = position["before"] ? index : index + 1
        copy = list.dup
        copy.insert(insert_at, item)
        copy
      end

      Ident = Struct.new(:row) do
        def name_slug = row["name_slug"].to_s
        def id = row["id"].to_s
      end

      # Formulas read sibling attributes. A default value is not a reference:
      # remove_attribute drops it along with the attribute.
      def attribute_in_use?(slug)
        attributes.any? do |attr|
          next false if attr["name_slug"].to_s == slug

          formula = attr["formula"].to_s
          formula.present? && formula.match?(/\b#{Regexp.escape(slug)}\b/)
        end
      end

      # An aggregate's source_slug and filter name attributes of the bridge it
      # aggregates through, so they pin bridge attributes, not siblings.
      def bridge_attribute_in_use?(related_entity, slug)
        attributes.any? do |attr|
          next false unless attr["type"].to_s == Entity::COMPUTED_TYPE

          config = attr["config"].is_a?(Hash) ? attr["config"].stringify_keys : {}
          next false unless config["target_entity_name"].to_s == related_entity
          next false unless config["bridge_role"].to_s.presence.in?([nil, "source"])

          config["source_slug"].to_s == slug || config.dig("filter", "slug").to_s == slug
        end
      end

      def group_to_stored(group)
        group = stringify(group)
        stored = {}
        stored["id"] = group["key"] if group.key?("key")
        %w[name description icon color].each { |key| stored[key] = group[key] if group.key?(key) }
        stored
      end

      def group_from_stored(group)
        group = stringify(group)
        public = { "key" => group["id"] }
        %w[name description icon color].each { |key| public[key] = group[key] if group.key?(key) }
        public
      end

      def association_to_stored(assoc)
        mapper.to_definition("associations" => [assoc])["associations"].first || {}
      end

      def missing_attribute(slug, dictionary: nil)
        dictionary ||= attributes.map { |attr| attr["name_slug"].to_s }
        candidates = Operations::Violation.candidates(slug, dictionary)
        add_violation(
          join("slug"),
          "attribute.not_found",
          { "slug" => slug, "candidates" => candidates },
          candidates.empty? ? "ask_user" : "fix_payload"
        )
      end

      def missing_group(key, pointer)
        candidates = Operations::Violation.candidates(key, groups.map { |group| group["id"].to_s })
        add_violation(
          pointer,
          "group.not_found",
          { "key" => key, "candidates" => candidates },
          candidates.empty? ? "ask_user" : "fix_payload"
        )
      end

      def missing_association(name)
        candidates = Operations::Violation.candidates(name, associations.map { |assoc| assoc["associated_entity_name"].to_s })
        add_violation(
          join("related_entity"),
          "association.not_found",
          { "name" => name, "candidates" => candidates },
          candidates.empty? ? "ask_user" : "fix_payload"
        )
      end

      # A patch that changes kind or html_type leaves the attribute's old
      # options / file / formula / aggregate behind in the merged copy. Those
      # inherited fields are dropped, as the editor resets them; one the patch
      # sets itself contradicts the new shape and is reported instead.
      def drop_inapplicable_fields!(attr)
        explicit = stringify(@change["set"]).reject { |_key, value| value.nil? }.keys
        kind = attr["kind"].to_s.presence || "input"
        html_type = attr["html_type"].to_s
        applicable = {
          "options" => kind == "input" && HtmlTypeOptions::SELECTION_TYPES.include?(html_type),
          "file" => kind == "input" && HtmlTypeOptions::CONFIG_TYPES.fetch(:file).include?(html_type),
          "formula" => kind == "calculated",
          "aggregate" => kind == "computed"
        }
        applicable.each do |field, fits|
          next if fits || !attr.key?(field)

          if explicit.include?(field)
            details = %w[options file].include?(field) ? { "html_type" => html_type } : { "kind" => kind }
            add_violation(join("set", field), "#{field}.not_applicable", details)
          end
          attr.delete(field)
        end
      end

      def add_violation(pointer, code, details, resolution = nil)
        @violations << Operations::Violation.new(
          pointer: pointer,
          code: code,
          details: details,
          resolution: resolution
        )
      end

      def remember(kind, id, pointer)
        @origins["#{kind}:#{id}"] = pointer
      end

      def pointer
        join
      end

      def join(*parts)
        Operations::Pointer.join(@pointer_prefix, @index, *parts)
      end

      def stringify(value)
        MergePatch.stringify(value)
      end

      def deep_copy(value)
        JSON.parse(JSON.generate(stringify(value)))
      end
    end
  end
end
