# frozen_string_literal: true

class PageContentGenerator
  module LayoutElements
    LAYOUT_GENERATORS = {
      "section"      => :generate_section_element,
      "divider"      => :generate_divider_element,
      "heading"      => :generate_heading_element,
      "paragraph"    => :generate_paragraph_element,
      "spacer"       => :generate_spacer_element,
      "alert"        => :generate_alert_element,
      "image"        => :generate_image_element,
      "callout"      => :generate_callout_element,
      "quote"        => :generate_quote_element,
      "button"       => :generate_button_element,
      "video"        => :generate_video_element,
      "list"         => :generate_list_element,
      "code_block"   => :generate_code_block_element,
      "card"         => :generate_card_element,
      "progress_bar" => :generate_progress_bar_element,
      "columns"      => :generate_columns_element
    }.freeze

    private

    def generate_layout_element(field)
      generator = LAYOUT_GENERATORS[field["field_type"]]
      unless generator
        sanitized = field["field_type"].to_s.gsub(/[^a-zA-Z0-9_\-]/, "_").gsub('"', '\\"')
        return "<%# skipped layout element: unknown field_type \"#{sanitized}\" %>"
      end

      escaped_field_id = ERB::Util.html_escape(field["id"])

      content = send(generator, field)
      <<~ERB.strip
            <div data-field-id="#{escaped_field_id}">
              #{content}
            </div>
      ERB
    end

    def generate_section_element(field)
      kwargs = { title: rb_str(field["label"] || "Section") }
      kwargs[:description] = rb_str(field["content"]) if field["content"].present?

      variant = %w[linked].include?(field["variant"]) ? field["variant"] : nil
      kwargs[:variant] = "\"#{variant}\"" if variant

      render_component_erb("FormFields::SectionElementComponent", kwargs)
    end

    def generate_divider_element(field)
      kwargs = { spacing: '"md"' }
      kwargs[:label] = rb_str(field["label"]) if field["label"].present? && !default_divider_label?(field["label"])

      render_component_erb("FormFields::DividerElementComponent", kwargs)
    end

    # The generator writes the divider label in the generating locale; a
    # default label is a placeholder, not text for the form.
    def default_divider_label?(label)
      I18n.available_locales.any? { |locale| I18n.t("maint_core.pages.generator.layout.divider", locale: locale) == label }
    end

    def generate_heading_element(field)
      text = field["content"].presence || field["label"] || "Heading"
      level = (field["heading_level"] || "h3").delete_prefix("h").to_i.clamp(1, 6)

      kwargs = { text: rb_str(text), level: level.to_s }
      kwargs[:alignment] = "\"#{field['alignment']}\"" if %w[left center right].include?(field["alignment"])

      render_component_erb("FormFields::HeadingElementComponent", kwargs)
    end

    def generate_paragraph_element(field)
      text = field["content"].presence || field["label"] || ""

      kwargs = { content_text: rb_str(text) }
      kwargs[:alignment] = "\"#{field['alignment']}\"" if %w[left center right].include?(field["alignment"])

      render_component_erb("FormFields::ParagraphElementComponent", kwargs)
    end

    def generate_spacer_element(field)
      height = %w[sm md lg xl].include?(field["spacer_height"]) ? field["spacer_height"] : "md"

      render_component_erb("FormFields::SpacerElementComponent", { height: "\"#{height}\"" })
    end

    def generate_alert_element(field)
      variant = %w[info warning success danger].include?(field["alert_variant"]) ? field["alert_variant"] : "info"

      render_component_erb("FormFields::AlertElementComponent", {
        content_text: rb_str(field["content"].presence || ""),
        variant:      "\"#{variant}\""
      })
    end

    def generate_image_element(field)
      kwargs = {
        image_url: rb_str(field["image_url"].presence || ""),
        alt_text:  rb_str(field["alt_text"].presence || "")
      }
      kwargs[:alignment] = "\"#{field['alignment']}\"" if %w[left center right].include?(field["alignment"])

      render_component_erb("FormFields::ImageElementComponent", kwargs)
    end

    def generate_callout_element(field)
      render_component_erb("FormFields::CalloutElementComponent", {
        content_text: rb_str(field["content"].presence || "")
      })
    end

    def generate_quote_element(field)
      kwargs = { content_text: rb_str(field["content"].presence || "") }
      kwargs[:attribution] = rb_str(field["attribution"]) if field["attribution"].present?

      render_component_erb("FormFields::QuoteElementComponent", kwargs)
    end

    def generate_button_element(field)
      text    = field["content"].presence || field["label"] || "Button"
      url     = field["button_url"].presence || "#"
      variant = %w[primary secondary outline].include?(field["button_variant"]) ? field["button_variant"] : "primary"
      size    = %w[sm md lg].include?(field["button_size"]) ? field["button_size"] : "md"
      align   = %w[left center right].include?(field["alignment"]) ? field["alignment"] : "left"

      render_component_erb("FormFields::ButtonElementComponent", {
        content_text:   rb_str(text),
        button_url:     rb_str(url),
        button_variant: "\"#{variant}\"",
        button_size:    "\"#{size}\"",
        alignment:      "\"#{align}\""
      })
    end

    def generate_columns_element(field)
      layout  = field["column_layout"] || "50-50"
      columns = field["columns"] || []

      # Each column wrapper needs a space-y-* class to maintain intra-column
      # field spacing after self-margins are removed from individual elements.
      # space-y-* on ContentComponent only reaches direct children; inside a
      # columns element, each column is its own subtree with no inherited space-y.
      col_spacing = resolve_field_spacing(@theme)

      columns_content = columns.map do |col|
        col_fields = col["fields"] || []
        "<div class=\"#{col_spacing}\">#{generate_fields(col_fields)}</div>"
      end.join("\n            ")

      render_component_erb("FormFields::ColumnsElementComponent",
        { column_layout: rb_str(layout) },
        block: columns_content)
    end

    def generate_video_element(field)
      alignment = %w[left center right].include?(field["alignment"]) ? field["alignment"] : "center"

      render_component_erb("FormFields::VideoElementComponent", {
        video_url: rb_str(field["video_url"].presence || ""),
        alignment: "\"#{alignment}\""
      })
    end

    def generate_list_element(field)
      style = %w[bullet numbered none].include?(field["list_style"]) ? field["list_style"] : "bullet"

      render_component_erb("FormFields::ListElementComponent", {
        content_text: rb_str(field["content"].presence || ""),
        list_style:   "\"#{style}\""
      })
    end

    def generate_code_block_element(field)
      kwargs = { content_text: rb_str(field["content"].presence || "") }
      kwargs[:code_language] = rb_str(field["code_language"]) if field["code_language"].present?

      render_component_erb("FormFields::CodeBlockElementComponent", kwargs)
    end

    def generate_card_element(field)
      render_component_erb("FormFields::CardElementComponent", {
        title:        rb_str(field["label"] || "Card"),
        content_text: rb_str(field["content"].presence || "")
      })
    end

    def generate_progress_bar_element(field)
      value = (field["progress_value"] || 0).to_i.clamp(0, 100)
      color = %w[indigo green blue red].include?(field["progress_color"]) ? field["progress_color"] : "indigo"

      render_component_erb("FormFields::ProgressBarElementComponent", {
        label:          rb_str(field["label"] || ""),
        progress_value: value.to_s,
        progress_color: "\"#{color}\""
      })
    end
  end
end
