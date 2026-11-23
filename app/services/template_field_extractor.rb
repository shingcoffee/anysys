# frozen_string_literal: true

# Extracts entity attributes and attribute groups from a page layout template's
# preview_rows.
#
# Maps preview element types to HTML types (deduplicating fields with the same
# label by appending a numeric suffix), and turns each `:section` element into a
# group whose name is the section label. Every field is tagged with the
# `group_key` of the section it falls under (nil when it precedes the first
# section). Sections that capture no fields are dropped.
#
# @example
#   template = PageLayoutTemplates.find("contact_simple")
#   result  = TemplateFieldExtractor.call(template)
#   # => { fields: [{ name: "Name", name_slug: "name", html_type: "text", group_key: nil }, ...],
#   #      groups: [{ key: "section_0", label: "Contact" }, ...] }
#
class TemplateFieldExtractor
  # Preview types that represent actual form fields (not layout elements)
  FIELD_TYPES = %i[input textarea select checkbox radio date number file].freeze

  # Maps preview element type to html_type
  TYPE_MAP = {
    input:    "text",
    textarea: "textarea",
    select:   "select",
    checkbox: "checkbox",
    radio:    "radio",
    date:     "date",
    number:   "number",
    file:     "file"
  }.freeze

  # Label patterns that override the default html_type for :input elements
  LABEL_HTML_TYPE_OVERRIDES = {
    /\bemail\b/i   => "email",
    /\bphone\b/i   => "tel",
    /\btel\b/i     => "tel",
    /\burl\b/i     => "url",
    /\bwebsite\b/i => "url",
    /\bpassword\b/i => "password"
  }.freeze

  def self.call(template)
    new(template).call
  end

  def initialize(template)
    @template = template
  end

  def call
    return { fields: [], groups: [] } unless @template && @template[:preview_rows]

    fields = []
    groups = []
    seen_slugs = {}
    current_group_key = nil
    section_index = -1

    @template[:preview_rows].each do |row|
      row.each do |element|
        type_sym = element[:type]

        if type_sym == :section
          label = element[:label]
          next if label.blank?

          section_index += 1
          current_group_key = "section_#{section_index}"
          groups << { key: current_group_key, label: label }
          next
        end

        next unless FIELD_TYPES.include?(type_sym)

        label = element[:label]
        next if label.blank?

        html_type = TYPE_MAP[type_sym]
        html_type = infer_html_type_from_label(label, html_type)

        slug = generate_slug(label)
        slug = deduplicate_slug(slug, seen_slugs)
        seen_slugs[slug] = true

        fields << {
          name: label,
          name_slug: slug,
          html_type: html_type,
          description: "",
          validators: [],
          group_key: current_group_key
        }
      end
    end

    used_keys = fields.filter_map { |f| f[:group_key] }.uniq
    groups.select! { |g| used_keys.include?(g[:key]) }

    { fields: fields, groups: groups }
  end

  private

  def infer_html_type_from_label(label, default_html_type)
    return default_html_type unless default_html_type == "text"

    LABEL_HTML_TYPE_OVERRIDES.each do |pattern, html_type|
      return html_type if label.match?(pattern)
    end

    default_html_type
  end

  def generate_slug(name)
    name.to_s.strip
        .unicode_normalize(:nfd)
        .gsub(/[\u0300-\u036f]/, "")
        .downcase
        .gsub(/[^a-z0-9\s\-_]/, "")
        .gsub(/[\s\-_]+/, "_")
        .gsub(/\A_|_\z/, "")
  end

  def deduplicate_slug(slug, seen)
    return slug unless seen.key?(slug)

    counter = 2
    loop do
      candidate = "#{slug}_#{counter}"
      return candidate unless seen.key?(candidate)
      counter += 1
    end
  end
end
