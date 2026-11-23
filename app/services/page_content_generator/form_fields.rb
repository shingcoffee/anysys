# frozen_string_literal: true

class PageContentGenerator
  module FormFields
    private

    def generate_form_field(field)
      field = identity_field_for_render(field)
      component = HTML_TYPE_COMPONENTS[field["html_type"]]
      unless component
        slug = (field["property_slug"] || field["id"] || "unknown").to_s.gsub(/[^a-zA-Z0-9_.\-]/, "_")
        unknown_type = field["html_type"].to_s.gsub(/[^a-zA-Z0-9_.\-]/, "_")
        fallback_comment = "<%# fallback: field \"#{slug}\" has unknown html_type \"#{unknown_type}\" %>"

        raw_slug = field["property_slug"] || field["id"] || "field_#{SecureRandom.hex(4)}"
        field_name = build_nested_field_name(field, raw_slug)
        field_id = field["id"] || "field_#{SecureRandom.hex(4)}"
        escaped_field_id = ERB::Util.html_escape(field_id)

        kwargs = {
          field_name: rb_str(field_name),
          label:      rb_str(field["label"]),
          required:   field_required?(field).to_s,
          value:      "page_prefill_value(#{rb_str(raw_slug)})",
          class:      '"w-full"'
        }
        kwargs[:disabled] = "true" if field_boundary.read_only_fields?

        fallback_erb = render_component_erb("FormFields::TextFieldComponent", kwargs)
        return <<~ERB.strip
          #{fallback_comment}
              <div data-field-id="#{escaped_field_id}">
                #{fallback_erb}#{field_error_erb(field, raw_slug)}
              </div>
        ERB
      end

      raw_slug = field["property_slug"] || field["id"] || "field_#{SecureRandom.hex(4)}"
      field_name = build_nested_field_name(field, raw_slug)
      field_id = field["id"] || "field_#{SecureRandom.hex(4)}"

      # User-provided values are interpolated into a Ruby string literal that
      # becomes generated ERB source, so they are emitted via `rb_str` (which
      # uses String#inspect) — NOT html_escape — to prevent Ruby/ERB injection.
      # The ViewComponent HTML-escapes them on output.
      kwargs = {
        field_name:  rb_str(field_name),
        label:       rb_str(field["label"]),
        required:    field_required?(field).to_s,
        placeholder: rb_str(field["placeholder"]),
        value:       "page_prefill_value(#{rb_str(raw_slug)})",
        class:       '"w-full"'
      }

      kwargs[:input_type] = rb_str(field["html_type"]) if component == "FormFields::TextFieldComponent"
      kwargs[:multiple] = "true" if field["html_type"] == "multi-select"
      add_file_kwargs(kwargs, field) if component == "FormFields::FileUploadFieldComponent"

      # Computed fields and unbound UI previews are display-only.
      kwargs[:disabled] = "true" if field["storage"] == "computed" || field_boundary.read_only_fields?

      kwargs[:help_text] = rb_str(field["help_text"]) if field["help_text"].present?

      # Pass options for select, multi-select, and radio fields
      dynamic_opts_config = field["dynamic_options"]
      if dynamic_opts_config&.dig("options_source") == "entity_entries"
        options_var = build_dynamic_entity_options_param_value(field_id, dynamic_opts_config)
        kwargs[:options] = field["html_type"] == "radio" ?
          "#{options_var}.map { |label, value| { 'label' => label, 'value' => value } }" : options_var
        if field["html_type"] == "select" && !field_boundary.read_only_fields?
          kwargs[:quick_add] = "page_entity_quick_add(#{dynamic_opts_config['entity_id'].to_i}, " \
                               "#{rb_str(dynamic_opts_config['label_field'])})"
        end
      elsif field["options"].is_a?(Array) && field["options"].any?
        kwargs[:options] = build_options_param_value(field)
      end

      if field["conditions"].present? && field["conditions"].any?
        kwargs[:data] = "{ conditions: #{rb_literal(field["conditions"])} }"
      end

      escaped_field_id = ERB::Util.html_escape(field_id)
      preamble = dynamic_opts_config&.dig("options_source") == "entity_entries" ? build_dynamic_options_preamble(field_id, dynamic_opts_config) : ""

      component_erb = render_component_erb(component, kwargs)

      <<~ERB.strip
        #{preamble}
            <div data-field-id="#{escaped_field_id}">
              #{component_erb}#{field_error_erb(field, raw_slug)}
            </div>
      ERB
    end

    # Errors a refused submission left on a field of the page's own entity.
    def field_error_erb(field, slug)
      return "" unless Pages::FormParams.primary_field?(field)

      "\n              <%= page_field_error(#{rb_str(slug)}) %>"
    end

    # Build the options value (pre-serialized Ruby source) for select/radio fields.
    # Select component expects [label, value] pairs; radio expects hashes with string keys.
    def build_options_param_value(field)
      html_type = field["html_type"].to_s
      opts = field["options"]

      if %w[radio].include?(html_type)
        # Radio expects array of hashes: [{ "label" => "...", "value" => "..." }]
        items = opts.map do |o|
          %({ "label" => #{rb_str(o["label"])}, "value" => #{rb_str(o["value"])} })
        end
        "[#{items.join(', ')}]"
      else
        # Select/multi-select expects [label, value] pairs
        items = opts.map do |o|
          "[#{rb_str(o["label"])}, #{rb_str(o["value"])}]"
        end
        "[#{items.join(', ')}]"
      end
    end

    # Returns the raw Ruby source for the options variable reference (no key prefix).
    def build_dynamic_entity_options_param_value(field_id, _config)
      "_dyn_opts_#{field_id.to_s.gsub(/[^a-z0-9_]/, '_')}"
    end

    # ERB that lists the target entity's records at render time for the
    # viewing tenant and audience (shared pages have a NULL customer_id).
    # Entities::ReferenceOptions owns the label rule and never raises on bad
    # configuration, so the template needs no rescue.
    def build_dynamic_options_preamble(field_id, config)
      var_name = "_dyn_opts_#{field_id.to_s.gsub(/[^a-z0-9_]/, '_')}"

      <<~ERB.strip
        <%- __cid = Current.customer_id || @page.customer_id
            #{var_name} = Entities::ReferenceOptions.call(entity_id: #{config["entity_id"].to_i}, label_field: #{rb_str(config["label_field"].to_s)},
              customer_id: __cid, audience: EntityAttributeAudience.for_user(Current.user, customer_id: __cid), viewer: Current.user) -%>
      ERB
    end

    # Hidden field that passes the page ID with the form submission
    # so PublicPagesController can look up the page configuration for param routing.
    # `_continuation`, `_run` and `_journey` are read from controller ivars at
    # render time so a token is never interpolated into generated ERB source.
    def hidden_page_id_field
      %(<%= hidden_field_tag :_page_id, @page.id %>#{hidden_continuation_field}#{hidden_run_field}#{hidden_journey_field}#{locked_inputs_card})
    end

    def hidden_journey_field
      %(<%= hidden_field_tag :_journey, @journey_start_key if @journey_start_key.present? %>)
    end

    def journey_progress
      %(<%= render Journeys::ProgressComponent.new(journey: @journey, current_key: @journey_step&.key) if @journey %>)
    end

    # Passed to the form component as its +extra_action+, beside the submit button.
    def journey_step_actions
      "Journeys::StepActionsComponent.for(@journey_step)"
    end

    def hidden_continuation_field
      %(<%= hidden_field_tag :_continuation, @page_continuation if @page_continuation.present? %>)
    end

    def hidden_run_field
      %(<%= hidden_field_tag :_run, @page_run_token if @page_run_token.present? %>)
    end

    def locked_inputs_card
      %(<%= render Pages::LockedInputsComponent.new(page: @page, bindings: @page_bindings) if @page_bindings.present? %>)
    end

    # Builds a nested field name based on field source for structured param routing.
    #
    # Primary base model fields:  base[model_name][email]  (e.g., base[user][email])
    # Primary entity own fields:  entity[grade]
    # Bridge entity fields:       assoc[bridge_entity_name][enrollment_date]
    #
    # Fields without source metadata use flat names.
    def build_nested_field_name(field, slug)
      source = field["source"]
      section = field["source_section"]

      case source
      when "base_model"
        model_key = slugify_section(section)
        "base[#{model_key}][#{slug}]"
      when "entity"
        "entity[#{slug}]"
      when "bridge"
        section_key = slugify_section(section)
        "assoc[#{section_key}][#{slug}]"
      when "identity"
        Pages::FormParams.identity_field?(field) ? "identity[#{slug}]" : slug
      else
        slug
      end
    end

    def identity_field_for_render(field)
      return field unless Pages::FormParams.identity_field?(field)

      Pages::FormParams.identity_key(field) == "email" ? field.merge("html_type" => "email") : field
    end

    def slugify_section(section)
      SectionSlug.for(section)
    end

    # The bound File or Image attribute decides whether the input takes several
    # files and which types it offers; an Image field offers images by default.
    def add_file_kwargs(kwargs, field)
      attribute = field_boundary.file_attribute(field)
      config = attribute && attribute["config"].is_a?(Hash) ? attribute["config"] : {}
      multiple = attribute ? EntityEntry.multiple_files?(attribute) : field["multiple"] == true
      accept = config["accept"].presence || ("image/*" if field["html_type"] == "image")
      kwargs[:multiple] = "true" if multiple
      kwargs[:accept] = rb_str(accept.to_s) if accept
    end

    # Page authors can mark a field required. Otherwise the marker follows the
    # bound attribute's presence validator for the audience viewing the form.
    def field_required?(field)
      field["required"] == true || field_boundary.required_field?(field)
    end
  end
end
