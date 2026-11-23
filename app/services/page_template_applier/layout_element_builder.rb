# frozen_string_literal: true

class PageTemplateApplier
  # Builds layout-element hashes (section headers, dividers, spacers, headings) with labels translated at generation time.
  # and resolves source-section label text and variant.
  #
  # All methods are stateless class methods so callers can invoke them without
  # instantiating a builder object.
  class LayoutElementBuilder
    ELEMENT_EXTRAS = {
      "divider" => {},
      "spacer"  => { "spacer_height" => "md" },
      "heading" => { "heading_level" => "h3" }
    }.freeze

    def self.section_header(label, variant: nil)
      header = {
        "id"            => "section_#{SecureRandom.hex(8)}",
        "field_type"    => "section",
        # A translated label such as "关联：学生" parameterizes to "".
        "property_slug" => label.parameterize(separator: "_").presence || "section",
        "property_type" => "layout",
        "label"         => label,
        "content"       => "",
        "placeholder"   => "",
        "help_text"     => "",
        "required"      => false,
        "width"         => "full",
        "order"         => 0
      }
      header["variant"] = variant if variant.present?
      header
    end

    def self.source_section_label(source, source_section)
      case source
      when "base_model" then [source_section.humanize, nil]
      when "entity"     then [source_section, nil]
      when "bridge"     then [I18n.t("maint_core.pages.generator.sections.linked", name: source_section), "linked"]
      else                   [I18n.t("maint_core.pages.generator.sections.other_fields"), nil]
      end
    end

    def self.layout_element(type)
      defaults = element_defaults(type)
      {
        "id"            => "#{type}_#{SecureRandom.hex(8)}",
        "field_type"    => type,
        "property_slug" => "#{type}_#{SecureRandom.hex(4)}",
        "property_type" => "layout",
        "label"         => defaults[:label],
        "content"       => "",
        "placeholder"   => "",
        "help_text"     => "",
        "required"      => false,
        "width"         => "full",
        "order"         => 0
      }.merge(defaults[:extra])
    end

    def self.element_defaults(type)
      extra = ELEMENT_EXTRAS.fetch(type.to_s) { raise ArgumentError, "unknown layout element type: #{type.inspect}" }
      { label: I18n.t("maint_core.pages.generator.layout.#{type}"), extra: extra }
    end
  end
end
