# frozen_string_literal: true

# Applies a layout template's rules to a page tab's fields.
#
# Takes a field array and rearranges it according to the template's
# width rules, section groupings, and injected layout elements
# (dividers/spacers).
#
# @example
#   result = PageTemplateApplier.call(fields, "contact_profile")
#   result[:fields]   # => rearranged fields with widths and sections
#   result[:theme]    # => theme preset key (e.g. "modern")
#   result[:settings] # => additional settings hash
#
class PageTemplateApplier
  require_relative "page_template_applier/layout_element_builder"
  require_relative "page_template_applier/field_preprocessor"
  require_relative "page_template_applier/field_grouper"

  def self.call(fields, template_key, entity: nil)
    new(fields, template_key, entity: entity).call
  end

  # True when a #call result's fields are already shaped as an array of page
  # hashes (multi-page layout) rather than a flat field list. Callers use this
  # to decide whether to wrap the result in a single default page.
  def self.paginated_result?(result_fields)
    result_fields.is_a?(Array) &&
      result_fields.first.is_a?(Hash) &&
      result_fields.first.key?("fields")
  end

  def initialize(fields, template_key, entity: nil)
    @fields      = deep_dup(fields)
    @template    = PageLayoutTemplates.find(template_key)
    @entity      = entity
    @preprocessor = FieldPreprocessor.new(@fields)
    @grouper      = FieldGrouper.new(@entity)
  end

  def call
    return { fields: @fields, theme: nil, settings: {} } unless @template

    layout = @template[:layout]

    result_fields =
      if layout[:multi_page]
        build_multi_page(layout)
      else
        apply_single_page(layout)
      end

    { fields: result_fields, theme: @template[:theme_preset], settings: {} }
  end

  private

  def apply_single_page(layout)
    working_fields = @preprocessor.separate
    @preprocessor.apply_visibility_filter!(working_fields[:entity_fields], layout)
    @preprocessor.apply_width_rules(working_fields[:entity_fields], layout)
    @preprocessor.apply_mobile_stack!(working_fields[:entity_fields], layout)

    case layout[:group_by]
    when :source
      result = @grouper.reorganize_by_source(working_fields, layout)
      return @grouper.apply_ordering(result)
    when :attribute_groups
      result = @grouper.reorganize_by_attribute_groups(working_fields, layout)
      return @grouper.apply_ordering(result)
    end

    if layout[:sections].present? && layout[:sections].any?
      result = @grouper.reorganize_into_sections(working_fields, layout)
      result = @grouper.inject_layout_elements(result, layout)
      @grouper.apply_ordering(result)
      result
    else
      flat = working_fields[:section_headers] + working_fields[:entity_fields]
      @grouper.apply_ordering(flat)
      flat
    end
  end

  def build_multi_page(layout)
    working_fields = @preprocessor.separate
    entity_fields  = working_fields[:entity_fields]
    @preprocessor.apply_visibility_filter!(entity_fields, layout)
    pages_count = layout[:pages_count] || 3

    @preprocessor.apply_width_rules(entity_fields, layout)
    @preprocessor.apply_mobile_stack!(entity_fields, layout)

    chunk_size = (entity_fields.length.to_f / pages_count).ceil
    chunks     = entity_fields.each_slice([chunk_size, 1].max).to_a

    chunks.each_with_index.map do |page_fields, idx|
      page_fields.each_with_index { |f, i| f["order"] = i }
      {
        "id"     => "page_#{idx + 1}",
        "name"   => "Step #{idx + 1}",
        "order"  => idx + 1,
        "fields" => page_fields
      }
    end
  end

  def deep_dup(obj)
    case obj
    when Array then obj.map { |e| deep_dup(e) }
    when Hash  then obj.transform_values { |v| deep_dup(v) }
    else            obj
    end
  end
end
