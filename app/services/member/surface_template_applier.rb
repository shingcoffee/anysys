# frozen_string_literal: true

module Member
  # Projects a PageLayoutTemplates DEFINITION into a Member::Surface::Detail.
  # Reuses PageTemplateApplier for the heavy lifting (visibility filter, width
  # assignment, attribute-group sectioning) and translates the resulting field
  # array into the row-and-section shape DetailGridComponent consumes.
  class SurfaceTemplateApplier
    DEFAULT_TEMPLATE_KEY = "member_default"

    def self.call(entity:, template_key: DEFAULT_TEMPLATE_KEY)
      new(entity, template_key).call
    end

    def initialize(entity, template_key)
      @entity        = entity
      @template      = PageLayoutTemplates.find(template_key)
      @template_key  = template_key
    end

    def call
      return nil unless @template

      laid_out = PageTemplateApplier.call(synthesize_fields, @template_key, entity: @entity)[:fields]

      Member::Surface::Detail.new(
        title:    ->(entry) { "##{entry.id}" },
        subtitle: ->(entry) { I18n.l(entry.created_at, format: :long) },
        sections: build_sections(laid_out)
      )
    end

    private

    # Computed fields render on the member detail alongside stored attributes; the
    # template's audience visibility filter still applies to them normally.
    def synthesize_fields
      (@entity.input_fields + @entity.computed_fields).filter_map do |attr|
        slug = (attr["name_slug"] || attr["key"]).to_s
        next nil if slug.empty?

        label = attr["display_label"].presence || attr["name"].presence || slug
        {
          "id"            => slug,
          "name_slug"     => slug,
          "html_type"     => attr["html_type"].presence || "text",
          "group_id"      => attr["group_id"],
          "visibility"    => attr["visibility"],
          "display_label" => label,
          "property_type" => "input"
        }
      end
    end

    def build_sections(laid_out)
      sections = []
      current  = nil

      laid_out.each do |f|
        if section_header?(f)
          sections << current if current
          current = { key: f["property_slug"].to_sym, title: f["label"], rows: [] }
        elsif layout_element?(f)
          next
        else
          current ||= { key: :primary, title: nil, rows: [] }
          current[:rows] << build_row(f)
        end
      end

      sections << current if current
      sections
    end

    def section_header?(f)
      f["property_type"] == "layout" && f["field_type"] == "section"
    end

    def layout_element?(f)
      f["property_type"] == "layout"
    end

    def build_row(f)
      slug = f["name_slug"]
      {
        key:   slug.to_sym,
        label: f["display_label"],
        span:  f["width"] == "full" ? 2 : 1,
        value: ->(entry) { entry.respond_to?(:display_text) ? entry.display_text(slug) : nil }
      }
    end
  end
end
