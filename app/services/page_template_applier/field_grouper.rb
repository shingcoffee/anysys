# frozen_string_literal: true

class PageTemplateApplier
  # Groups a flat list of entity fields into ordered sections and injects
  # dividers/spacers/headings between them according to the layout config.
  #
  # Depends on LayoutElementBuilder for building individual element hashes.
  class FieldGrouper
    def initialize(entity, builder: LayoutElementBuilder)
      @entity  = entity
      @builder = builder
    end

    # Groups fields by (source, source_section) pairs and emits a section
    # header (and preceding divider) each time the pair changes.
    def reorganize_by_source(working_fields, _layout)
      entity_fields = working_fields[:entity_fields]
      result        = []
      current_group = nil

      entity_fields.each do |field|
        source         = field["source"].to_s
        source_section = field["source_section"].to_s
        source_section_label = field["source_section_label"].presence || source_section
        group_key      = [source, source_section]

        if current_group != group_key
          result << @builder.layout_element("divider") if current_group && result.any?

          label, variant = @builder.source_section_label(source, source_section_label)
          result << @builder.section_header(label, variant: variant)
          current_group = group_key
        end

        result << field
      end

      result
    end

    # Groups the entity's own fields by its curated attribute_groups_json
    # order, with ungrouped ones under a trailing "Additional" section. Link
    # fields always get their own "Linked: <entity>" section after them.
    # Falls back to source-based grouping when @entity is absent or has no
    # named groups.
    def reorganize_by_attribute_groups(working_fields, layout)
      groups = Array(@entity&.attribute_groups_json)
      return reorganize_by_source(working_fields, layout) unless groups.any? { |g| g["name"].to_s.strip != "" }

      entity_fields, link_fields = working_fields[:entity_fields].partition { |field| field["source"].to_s != "bridge" }
      result        = []
      placed_ids    = Set.new

      groups.each do |g|
        name = g["name"].to_s
        next if name.empty?

        members = entity_fields.select { |f| f["group_id"] == g["id"] && !placed_ids.include?(f["id"]) }
        next if members.empty?

        result << @builder.layout_element("divider") if result.any?
        result << @builder.section_header(name)
        members.each { |f| placed_ids << f["id"]; result << f }
      end

      ungrouped = entity_fields.reject { |f| placed_ids.include?(f["id"]) }
      if ungrouped.any?
        result << @builder.layout_element("divider") if result.any?
        result << @builder.section_header(I18n.t("maint_core.pages.generator.sections.additional"))
        result.concat(ungrouped)
      end

      append_link_sections(result, link_fields)
    end

    # Groups fields into sections defined by layout[:sections] (each section
    # matches on html_type).  Unmatched fields are appended under "Other Fields".
    def reorganize_into_sections(working_fields, layout)
      sections_config = layout[:sections]
      entity_fields   = working_fields[:entity_fields]
      result          = []
      placed_ids      = Set.new

      sections_config.each do |section|
        matching = entity_fields.select do |f|
          !placed_ids.include?(f["id"]) && section[:match_types].include?(f["html_type"].to_s)
        end
        next if matching.empty?

        result << @builder.section_header(section[:label])
        matching.each { |f| placed_ids << f["id"]; result << f }
      end

      unmatched = entity_fields.reject { |f| placed_ids.include?(f["id"]) }
      if unmatched.any?
        result << @builder.section_header(I18n.t("maint_core.pages.generator.sections.other_fields"))
        result.concat(unmatched)
      end

      result
    end

    # Inserts dividers/spacers/headings at the positions defined by
    # layout[:inject_elements].  Each element specifies { type:, after_section: N }
    # where N is the zero-based index into section headers found in +fields+.
    def inject_layout_elements(fields, layout)
      elements = layout[:inject_elements] || []
      return fields if elements.empty?

      section_indices = fields.each_with_index
                              .select { |f, _| f["property_type"] == "layout" && f["id"]&.start_with?("section_") }
                              .map { |_, i| i }

      insertions = {}
      elements.each do |el|
        section_idx = el[:after_section]
        next unless section_idx

        header_pos = section_indices[section_idx]
        next unless header_pos

        next_header_pos = section_indices[section_idx + 1]
        insert_at       = next_header_pos || fields.length

        insertions[insert_at] ||= []
        insertions[insert_at] << @builder.layout_element(el[:type])
      end

      result = fields.dup
      insertions.keys.sort.reverse.each do |pos|
        insertions[pos].each { |el| result.insert(pos, el) }
      end

      result
    end

    # Resequences all order values to match the array position.
    # Mutates in place and returns +fields+.
    def apply_ordering(fields)
      fields.each_with_index { |f, i| f["order"] = i }
      fields
    end

    private

    def append_link_sections(result, link_fields)
      link_fields.group_by { |field| field["source_section"].to_s }.each_value do |members|
        result << @builder.layout_element("divider") if result.any?
        label, variant = @builder.source_section_label(
          "bridge", members.first["source_section_label"].presence || members.first["source_section"].to_s
        )
        result << @builder.section_header(label, variant: variant)
        result.concat(members)
      end
      result
    end
  end
end
