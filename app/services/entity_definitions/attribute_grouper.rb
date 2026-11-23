# frozen_string_literal: true

module EntityDefinitions
  # Applies LLM-supplied attribute groups from the same entity fill as
  # property_schema. Does not invent groups or reorder sections — the model
  # chooses membership and display order from the full collected attribute list.
  class AttributeGrouper
    Result = Struct.new(:groups, :attributes, keyword_init: true)

    ID_FORMAT = /\A[A-Za-z0-9_\-]{1,50}\z/
    GROUP_KEYS = %w[id name icon color description].freeze

    def self.call(attributes:, existing_groups: [], incoming_groups: nil)
      new(
        attributes: attributes,
        existing_groups: existing_groups,
        incoming_groups: incoming_groups
      ).call
    end

    def initialize(attributes:, existing_groups:, incoming_groups:)
      @attributes = Array(attributes).filter_map { |attr| dup_hash(attr) }
      @id_remap = {}
      @groups = merge_groups(Array(existing_groups), incoming_groups)
    end

    def call
      apply_group_ids
      Result.new(groups: @groups, attributes: @attributes)
    end

    private

    def dup_hash(row)
      return nil unless row.is_a?(Hash)

      row.deep_stringify_keys.dup
    end

    def merge_groups(existing, incoming)
      existing_list = existing.filter_map { |row| copy_existing_group(row) }
      return existing_list if incoming.nil?

      by_id = {}
      existing_list.each { |group| by_id[group["id"]] = group }

      ordered = []
      seen = Set.new
      Array(incoming).each do |row|
        incoming_group = normalize_incoming_group(row, existing_list + ordered)
        next unless incoming_group

        existing_group = by_id[incoming_group["id"]] ||
                         existing_list.find { |group| group["name"].to_s.strip.downcase == incoming_group["name"].downcase }
        if existing_group
          @id_remap[incoming_group["id"]] = existing_group["id"] if existing_group["id"] != incoming_group["id"]
          existing_group.merge!(incoming_group.except("id"))
          next if seen.include?(existing_group["id"])

          ordered << existing_group
          seen << existing_group["id"]
        else
          next if seen.include?(incoming_group["id"])

          ordered << incoming_group
          seen << incoming_group["id"]
        end
      end

      leftover = existing_list.reject { |group| seen.include?(group["id"]) }
      leftover + ordered
    end

    def copy_existing_group(row)
      group = dup_hash(row)
      return nil unless group
      return nil if group["id"].to_s.blank? || group["name"].to_s.strip.blank?

      slice_group(group)
    end

    def normalize_incoming_group(row, groups)
      row = dup_hash(row)
      return nil unless row

      name = row["name"].to_s.strip
      return nil if name.blank? || name.length > 60

      id = row["id"].to_s
      id = allocate_id(name, groups) if id !~ ID_FORMAT
      return nil if id !~ ID_FORMAT

      icon = row["icon"].to_s
      icon = EntityAttributeGroupOptions::DEFAULT_ICON unless EntityAttributeGroupOptions::ICONS.key?(icon)
      color = row["color"].to_s
      color = EntityAttributeGroupOptions::DEFAULT_COLOR unless EntityAttributeGroupOptions::COLORS.include?(color)

      group = { "id" => id, "name" => name, "icon" => icon, "color" => color }
      description = row["description"].to_s
      group["description"] = description if description.present?
      group
    end

    def apply_group_ids
      known = @groups.map { |group| group["id"] }.to_set
      @attributes.each do |attr|
        gid = remap_id(attr["group_id"])
        if gid.present? && known.include?(gid)
          attr["group_id"] = gid
        else
          attr.delete("group_id")
        end
      end
    end

    def remap_id(gid)
      value = gid.to_s
      return "" if value.blank?

      @id_remap[value] || value
    end

    def slice_group(group)
      group.slice(*GROUP_KEYS).tap do |sliced|
        sliced["id"] = group["id"].to_s
        sliced["name"] = group["name"].to_s.strip
        sliced.delete("description") if sliced["description"].to_s.blank?
      end
    end

    def allocate_id(seed, groups)
      taken = Array(groups).map { |group| group["id"] }
      base = "g_#{seed.to_s.parameterize(separator: '_')}"
      base = "g_group" if base.length < 3
      base = base[0, 50]
      id = base
      n = 2
      while taken.include?(id)
        suffix = "_#{n}"
        id = "#{base[0, 50 - suffix.length]}#{suffix}"
        n += 1
      end
      id
    end
  end
end
