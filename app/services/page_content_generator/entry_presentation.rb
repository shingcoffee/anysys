# frozen_string_literal: true

class PageContentGenerator
  # Lays an input page out as the admin entity entry form does
  # (Admin::Entities::EntryFormComponent) instead of in the page theme: one
  # form, each section a titled group of a two-column grid, and the entry
  # form's submit / Cancel bar. Every step of a multi-step page joins the one
  # form. Field types the entry form has no control for keep their page control.
  module EntryPresentation
    ENTRY_BOOLEAN_TYPES = %w[checkbox switch].freeze
    ENTRY_CHOICE_TYPES = %w[select multi-select radio].freeze

    private

    def generate_entry_form(pages_config, settings)
      submit_text = settings["submit_button_text"].present? ? rb_str(settings["submit_button_text"]) : "nil"
      groups = entry_groups(pages_config).filter_map do |group|
        cells = group[:fields].map { |field| entry_cell(field) }.reject(&:blank?)
        group.merge(cells: cells) if cells.any?
      end
      groups = groups.each_with_index.map { |group, index| entry_group_erb(group, separated: index.positive?) }

      <<~ERB.strip
        <%= render Admin::Pages::FormComponent.new(
          submit_text: #{submit_text},
          extra_action: #{journey_step_actions},
          **page_form_options
        ) do %>
          #{journey_progress}
          #{hidden_page_id_field}
          #{groups.join("\n      ")}
        <% end %>
      ERB
    end

    # Sections split each step into groups; fields ahead of a step's first
    # section form a group named after the step when there are several steps.
    # The rule between groups replaces a divider closing a section.
    def entry_groups(pages_config)
      several_steps = pages_config.size > 1
      pages_config.flat_map do |step|
        fields = without_hidden_sections(resolve_dynamic_options(step["fields"] || []))
        fields.slice_before { |field| layout_type?(field, "section") }.filter_map do |run|
          section = run.shift if layout_type?(run.first, "section")
          run.pop while run.any? && layout_type?(run.last, "divider")
          next if run.empty?

          label = section ? section["label"] : (step["name"] if several_steps)
          { label: label, description: section&.dig("content"), fields: run }
        end
      end
    end

    def entry_group_erb(group, separated:)
      kwargs = ["label: #{rb_str(group[:label])}", "separated: #{separated}"]
      kwargs << "description: #{rb_str(group[:description])}" if group[:description].present?

      "<%= render Admin::Entities::EntryGroupComponent.new(#{kwargs.join(', ')}) do %>\n      " \
        "#{group[:cells].join("\n      ")}\n    <% end %>"
    end

    def entry_cell(field)
      return %(<div class="min-w-0 md:col-span-2">#{generate_layout_element(field)}</div>) if field["property_type"] == "layout"
      return "" unless field_boundary.visible_field?(field)

      field = identity_field_for_render(field)
      control = entry_field_erb(field)
      return %(<div class="min-w-0 md:col-span-2">#{generate_field(field)}</div>) unless control

      span = " md:col-span-2" if Admin::Entities::EntryFieldComponent::FULL_WIDTH_TYPES.include?(field["html_type"])
      escaped_id = ERB::Util.html_escape(field["id"])
      cell =
        if field_boundary.read_only_fields?
          %(<fieldset disabled data-field-id="#{escaped_id}" class="min-w-0 border-0 p-0#{span}">#{control}</fieldset>)
        else
          %(<div data-field-id="#{escaped_id}" class="min-w-0#{span}">#{control}</div>)
        end
      unless_input_bound(field, cell)
    end

    # nil when the entry form has no control for the field; computed fields
    # and option-list checkboxes keep their page control.
    def entry_field_erb(field)
      html_type = field["html_type"].to_s
      return unless Admin::Entities::EntryFieldComponent::CONTROLS.key?(html_type)
      return if field["storage"] == "computed" || field["id"].blank?
      return if ENTRY_BOOLEAN_TYPES.include?(html_type) && field["options"].present?

      slug = (field["property_slug"] || field["id"]).to_s
      kwargs = {
        id: rb_str(field["id"]),
        slug: rb_str(slug),
        field_name: rb_str(build_nested_field_name(field, slug)),
        label: rb_str(field["label"]),
        html_type: rb_str(html_type),
        required: field_required?(field).to_s,
        value: entry_value_source(field, slug)
      }
      kwargs[:help_text] = rb_str(field["help_text"]) if field["help_text"].present?
      kwargs[:placeholder] = rb_str(field["placeholder"]) if field["placeholder"].present?
      kwargs[:data] = "{ conditions: #{rb_literal(field['conditions'])} }" if field["conditions"].present?
      kwargs[:errors] = "page_field_errors(#{rb_str(slug)})" if Pages::FormParams.primary_field?(field)

      preamble = ""
      dynamic = field["dynamic_options"]
      if dynamic&.dig("options_source") == "entity_entries"
        field_id = field["id"]
        preamble = build_dynamic_options_preamble(field_id, dynamic)
        kwargs[:options] = build_dynamic_entity_options_param_value(field_id, dynamic)
        if html_type == "select" && !field_boundary.read_only_fields?
          kwargs[:quick_add] = "page_entity_quick_add(#{dynamic['entity_id'].to_i}, #{rb_str(dynamic['label_field'])})"
        end
      elsif field["options"].is_a?(Array) && field["options"].any?
        kwargs[:options] = "[#{field['options'].map { |option| "[#{rb_str(option['label'])}, #{rb_str(option['value'])}]" }.join(', ')}]"
      end

      component = "<%= render Admin::Pages::FormFieldComponent.new(\n" \
                  "        #{kwargs.map { |key, value| "#{key}: #{value}" }.join(",\n        ")}\n      ) %>"
      "#{preamble}#{component}"
    end

    # The prefill (query values, or the edited entry's), else the value a new
    # entry starts with.
    def entry_value_source(field, slug)
      default = entry_default(field, slug)
      default_arg = ", default: #{rb_literal(default)}" unless default.nil?
      "page_prefill_value(#{rb_str(slug)}#{default_arg})"
    end

    def entry_default(field, slug)
      entity = page.entity
      return unless field["source"] == "entity" && entity

      defaults = entity.default_properties_json || {}
      value = defaults[slug]
      return value if entry_literal?(value)
      return unless ENTRY_CHOICE_TYPES.include?(field["html_type"])

      attribute = Array(entity.property_schema_json).grep(Hash).find { |item| item["name_slug"] == slug }
      selected = Array(attribute&.dig("config", "options")).grep(Hash).select { |option| option["default"] == true }
                                                           .map { |option| option["value"].to_s }
      field["html_type"] == "multi-select" ? selected.presence : selected.first
    end

    def entry_literal?(value)
      case value
      when String, Integer, TrueClass, FalseClass then true
      when Array then value.all? { |item| item.is_a?(String) || item.is_a?(Integer) }
      else false
      end
    end
  end
end
