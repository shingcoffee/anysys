# frozen_string_literal: true

# Builds the Page + rendered content used to preview a layout template.
#
# Shared by:
#   - Admin::Maintenance::EntityTemplatePreviewsController (entity-scoped: uses the
#     entity's curated fields when present, falling back to the template blueprint)
#   - Admin::Maintenance::TemplatePreviewsController (template-key-scoped: no entity,
#     used when previewing a template for a not-yet-saved entity)
#
# `ref_data` is the template hash (PageLayoutTemplates.find result) or the parsed
# `referenced_template` JSON — both carry :key, :name, :description and :preview_rows.
class TemplatePreviewBuilder
  def self.call(customer:, ref_data:, entity: nil)
    new(customer: customer, ref_data: ref_data, entity: entity).call
  end

  def initialize(customer:, ref_data:, entity: nil)
    @customer = customer
    @ref_data = ref_data.respond_to?(:with_indifferent_access) ? ref_data.with_indifferent_access : ref_data
    @entity   = entity
  end

  def call
    pages = build_pages
    result = nil

    pages = pages.map do |page|
      result = PageTemplateApplier.call(page["fields"], template_key, entity: @entity)
      applied_fields =
        if result[:fields].is_a?(Array) && result[:fields].first.is_a?(Hash) && result[:fields].first.key?("fields")
          result[:fields].flat_map { |p| p["fields"] }
        else
          result[:fields]
        end
      page.merge("fields" => applied_fields)
    end

    config = { "metadata" => {}, "pages" => pages }
    theme_key = result&.dig(:theme)
    config["theme"] = ThemeResolver::THEME_PRESETS[theme_key] if theme_key.present?

    page = Page.new(
      name: page_name,
      description: @ref_data[:description],
      customer: @customer,
      configuration: config.to_json
    )

    { page: page, content: PageContentGenerator.new(page).generate }
  end

  private

  def template_key
    @ref_data[:key]
  end

  def page_name
    @entity ? "#{@entity.display_label} — #{@ref_data[:name]}" : @ref_data[:name].to_s
  end

  # Prefer the entity's own curated fields; otherwise synthesize fields from the
  # template's preview blueprint so a template can be previewed without an entity.
  def build_pages
    pages = @entity ? PageFieldPopulator.call(@entity) : []
    return pages unless pages.empty?

    extracted = TemplateFieldExtractor.call(@ref_data.deep_symbolize_keys)
    fallback_fields = extracted[:fields].each_with_index.map do |f, i|
      {
        "id"            => "field_#{SecureRandom.hex(8)}",
        "field_type"    => f[:html_type],
        "property_slug" => f[:name_slug],
        "property_type" => f[:type] == "Integer" ? "integer" : "string",
        "label"         => f[:name],
        "placeholder"   => "",
        "help_text"     => "",
        "required"      => false,
        "width"         => "full",
        "order"         => i,
        "html_type"     => f[:html_type]
      }
    end
    [{ "id" => "page_1", "name" => "Form", "order" => 1, "fields" => fallback_fields }]
  end
end
