# frozen_string_literal: true

# PageContentGenerator
#
# Generates ERB template content from page configuration.
# Converts field configuration to ViewComponent-based form fields wrapped
# in a responsive TailwindCSS layout.
#
# @example
#   PageContentGenerator.new(page).generate
#   # => "<%= render FormFields::PageComponent.new(page: @page) do %>..."
#
class PageContentGenerator
  # Maps HTML input types to their corresponding ViewComponent classes (preferred)
  HTML_TYPE_COMPONENTS = {
    # Text group
    "text"     => "FormFields::TextFieldComponent",
    "textarea" => "FormFields::TextareaFieldComponent",
    "search"   => "FormFields::TextFieldComponent",
    "password" => "FormFields::TextFieldComponent",
    "hidden"   => "FormFields::TextFieldComponent",
    # Selection group
    "select"       => "FormFields::SelectFieldComponent",
    "multi-select" => "FormFields::SelectFieldComponent",
    "radio"        => "FormFields::RadioFieldComponent",
    "checkbox"     => "FormFields::CheckboxFieldComponent",
    "switch"       => "FormFields::ToggleFieldComponent",
    # Numeric group
    "number"   => "FormFields::NumberFieldComponent",
    "currency" => "FormFields::NumberFieldComponent",
    "range"    => "FormFields::NumberFieldComponent",
    "rating"   => "FormFields::RatingFieldComponent",
    # Date & Time group
    "date"           => "FormFields::DateFieldComponent",
    "time"           => "FormFields::TimeFieldComponent",
    "datetime-local" => "FormFields::DateFieldComponent",
    "month"          => "FormFields::DateFieldComponent",
    "week"           => "FormFields::DateFieldComponent",
    # Contact group
    "email" => "FormFields::EmailFieldComponent",
    "tel"   => "FormFields::TextFieldComponent",
    "url"   => "FormFields::TextFieldComponent",
    # Rich content group
    "rich-text" => "FormFields::TextareaFieldComponent",
    "signature" => "FormFields::TextFieldComponent",
    # Media & File group
    "file"  => "FormFields::FileUploadFieldComponent",
    "image" => "FormFields::FileUploadFieldComponent",
    "color" => "FormFields::TextFieldComponent"
  }.freeze

  DEFAULT_COMPONENT = "FormFields::TextFieldComponent"

  # Column grid helpers — mirrors the canvas editor's WIDTH_COLS / WIDTH_CLASSES
  WIDTH_COLS = { "full" => 12, "three_quarters" => 9, "two_thirds" => 8, "half" => 6, "third" => 4, "quarter" => 3 }.freeze
  COL_SPAN_CLASSES = { "full" => "col-span-12", "three_quarters" => "col-span-9", "two_thirds" => "col-span-8", "half" => "col-span-6", "third" => "col-span-4", "quarter" => "col-span-3" }.freeze
  # Breakpoint variants must be full literal strings — Tailwind's scanner cannot
  # discover interpolated "md:#{...}" classes, so they would compile to nothing.
  MD_COL_SPAN_CLASSES = { "full" => "md:col-span-12", "three_quarters" => "md:col-span-9", "two_thirds" => "md:col-span-8", "half" => "md:col-span-6", "third" => "md:col-span-4", "quarter" => "md:col-span-3" }.freeze
  LG_COL_SPAN_CLASSES = { "full" => "lg:col-span-12", "three_quarters" => "lg:col-span-9", "two_thirds" => "lg:col-span-8", "half" => "lg:col-span-6", "third" => "lg:col-span-4", "quarter" => "lg:col-span-3" }.freeze
  FULL_ROW_LAYOUT_TYPES = %w[section divider heading paragraph spacer alert callout quote columns card list code_block progress_bar video image button].freeze

  PRESENTATIONS = %i[themed entry].freeze

  include ThemeResolver
  include LayoutElements
  include FormFields
  include EntryPresentation

  # +presentation: :entry+ lays input pages out as the admin entity entry form
  # (see EntryPresentation); :themed follows the page's theme and steps.
  def initialize(page, presentation: :themed)
    raise ArgumentError, "unknown presentation #{presentation.inspect}" unless PRESENTATIONS.include?(presentation)

    @page = page
    @presentation = presentation
    @theme = page.configuration_json&.dig("theme") || {}
  end

  def generate
    return "" if page.configuration.blank?

    # Composite layout — delegate to CompositePageRenderer
    if page.configuration_json["layout"] == "composite"
      return generate_composite
    end

    pages_config = page.configuration_json["pages"] || []
    settings = page.configuration_json["form_settings"] || page.configuration_json["settings"] || {}

    # If pages_config is empty or has no fields, return empty
    return "" if pages_config.empty?
    return "" if pages_config.size == 1 && (pages_config.first["fields"] || []).empty?

    has_inputs = pages_config.any? { |p| page_has_input_fields?(p) }

    content = if !has_inputs
                generate_content_only(pages_config)
    elsif presentation == :entry
                generate_entry_form(pages_config, settings)
    elsif pages_config.size > 1
                generate_wizard(pages_config, settings)
    else
                generate_single_page(pages_config.first, settings)
    end

    wrap_with_runtime_controller(content)
  end

  private

  attr_reader :page, :theme, :presentation

  def page_has_input_fields?(page_config)
    fields = page_config["fields"] || []
    fields.any? do |f|
      if f["field_type"] == "columns"
        columns_have_inputs?(f)
      else
        f["property_type"] != "layout"
      end
    end
  end

  def columns_have_inputs?(column_field)
    (column_field["columns"] || []).any? do |col|
      (col["fields"] || []).any? { |f| f["property_type"] != "layout" }
    end
  end

  def generate_content_only(pages_config)
    all_fields = pages_config.flat_map { |p| p["fields"] || [] }
    all_fields = resolve_dynamic_options(all_fields)

    <<~ERB.strip
      <%= render FormFields::PageComponent.new(page: @page,
              theme: (@page.configuration_json["theme"] || {})) do %>
        <%= render FormFields::ContentComponent.new(theme: (@page.configuration_json["theme"] || {})) do %>
          #{generate_fields(all_fields)}
        <% end %>
      <% end %>
    ERB
  end

  def generate_single_page(page_config, settings)
    fields = page_config&.dig("fields") || []
    fields = resolve_dynamic_options(fields)
    # Encode both Ruby literals and ERB delimiters before template compilation.
    submit_text_expr = if settings["submit_button_text"].present?
                         rb_str(settings["submit_button_text"])
                       else
                         't("public_views.forms.submit")'
                       end

    <<~ERB.strip
      <%= render FormFields::PageComponent.new(page: @page,
              theme: (@page.configuration_json["theme"] || {})) do %>
        <%= render FormFields::FormComponent.new(
          action: @form_action,
          submit_text: #{submit_text_expr},
          theme: (@page.configuration_json["theme"] || {}),
          page: @page,
          extra_action: #{journey_step_actions}
        ) do %>
          #{journey_progress}
          #{hidden_page_id_field}
          #{generate_fields(fields)}
        <% end %>
      <% end %>
    ERB
  end

  def generate_wizard(pages_config, settings)
    submit_text_expr = if settings["submit_button_text"].present?
                         rb_str(settings["submit_button_text"])
                       else
                         't("public_views.forms.submit")'
                       end
    wizard_settings = page.configuration_json["wizard_settings"] || {}

    # Determine initial step from preview_active_page
    initial_step = 1
    preview_active_page = page.configuration_json["preview_active_page"]
    if preview_active_page.present?
      idx = pages_config.index { |p| p["id"] == preview_active_page }
      initial_step = idx + 1 if idx
    end

    steps_content = pages_config.each_with_index.map do |page_data, idx|
      step_fields = generate_fields(resolve_dynamic_options(page_data["fields"] || []))
      # Include hidden page_id in the first step (inside the wizard form)
      page_id_field = idx == 0 ? hidden_page_id_field : ""
      <<~ERB.strip
            <% wizard.with_step(id: #{rb_str(page_data['id'])}) do %>
              #{page_id_field}#{step_fields}
            <% end %>
      ERB
    end.join("\n      ")

    <<~ERB.strip
      <%= render FormFields::PageComponent.new(page: @page,
              theme: (@page.configuration_json["theme"] || {})) do %>
        <%= render FormFields::WizardComponent.new(
          pages: @page.configuration_json["pages"],
          action: @form_action,
          submit_text: #{submit_text_expr},
          show_progress: #{wizard_settings['show_progress'] != false},
          allow_back: #{wizard_settings['allow_back'] != false},
          initial_step: #{initial_step},
          theme: (@page.configuration_json["theme"] || {}),
          page: @page,
          extra_action: #{journey_step_actions}
        ) do |wizard| %>
          #{journey_progress}
          #{steps_content}
        <% end %>
      <% end %>
    ERB
  end

  def generate_fields(fields)
    fields = without_hidden_sections(fields)
    return "" if fields.empty?
    group_into_rows(fields).map { |row| render_field_row(row) }.join("\n      ")
  end

  # A section whose inputs the viewer can see none of is dropped with its
  # heading, the divider in front of it and its layout elements, so the form
  # shows no empty headings. Sections without inputs render as usual.
  def without_hidden_sections(fields)
    runs = fields.slice_before { |field| layout_type?(field, "section") }.to_a
    hidden = runs.map { |run| hidden_section?(run) }
    runs.each_with_index.flat_map do |run, index|
      next [] if hidden[index]

      hidden[index + 1] && layout_type?(run.last, "divider") ? run[0...-1] : run
    end
  end

  def hidden_section?(run)
    return false unless layout_type?(run.first, "section")

    inputs = run.flat_map { |field| section_inputs(field) }
    inputs.any? && inputs.none? { |field| field_boundary.visible_field?(field) }
  end

  def section_inputs(field)
    return [] unless field.is_a?(Hash)
    return Array(field["columns"]).grep(Hash).flat_map { |column| Array(column["fields"]).flat_map { |nested| section_inputs(nested) } } if field["field_type"] == "columns"

    field["property_type"] == "layout" ? [] : [field]
  end

  def layout_type?(field, type)
    field.is_a?(Hash) && field["property_type"] == "layout" && field["field_type"] == type
  end

  # Groups fields into visual rows respecting the 12-column grid, matching canvas logic.
  def group_into_rows(fields)
    rows = []
    current_row = []
    used_cols = 0

    fields.each do |field|
      is_full_row = field["property_type"] == "layout" &&
                    FULL_ROW_LAYOUT_TYPES.include?(field["field_type"])

      if is_full_row
        rows << current_row.dup unless current_row.empty?
        current_row.clear
        used_cols = 0
        rows << [field]
        next
      end

      cols = WIDTH_COLS[field["width"]] || 12
      if used_cols + cols > 12 && !current_row.empty?
        rows << current_row.dup
        current_row.clear
        used_cols = 0
      end

      current_row << field
      used_cols += cols
    end

    rows << current_row unless current_row.empty?
    rows
  end

  # Wraps a row of fields in a 12-column grid when more than one field shares the row.
  def render_field_row(row)
    return generate_field(row.first) if row.size == 1

    cells = row.map do |field|
      span = responsive_col_span(field)
      %(<div class="#{span}">\n      #{generate_field(field)}\n      </div>)
    end.join("\n      ")

    %(<div class="grid grid-cols-12 gap-x-4 items-end">\n      #{cells}\n      </div>)
  end

  def responsive_col_span(field)
    desktop_width = field["width"] || "full"
    responsive = field["responsive_widths"] || {}

    mobile_width = responsive["mobile"] || "full"
    tablet_width = responsive["tablet"] || desktop_width

    classes = []
    classes << (COL_SPAN_CLASSES[mobile_width] || "col-span-12")
    classes << (MD_COL_SPAN_CLASSES[tablet_width] || "md:col-span-12") if tablet_width != mobile_width
    classes << (LG_COL_SPAN_CLASSES[desktop_width] || "lg:col-span-12") if desktop_width != tablet_width
    classes.join(" ")
  end

  def generate_field(field)
    return generate_layout_element(field) if field["property_type"] == "layout"
    return "" unless field_boundary.visible_field?(field)

    # A field the audience sees but may not change shows the record's value
    # read-only, so a form that only creates records leaves it off.
    locked = !field_boundary.editable_field?(field)
    return "" if locked && !page.serves?(:update)

    content = generate_form_field(field)
    # Native fieldset disabling covers custom inputs/buttons as well as the
    # components that merge the disabled HTML attribute themselves.
    content = %(<fieldset disabled class="min-w-0 border-0 p-0">#{content}</fieldset>) if locked || field_boundary.read_only_fields?
    unless_input_bound(field, content)
  end

  # A locked input's field disappears when the run supplies its value; the
  # locked-inputs card shows the record instead.
  def unless_input_bound(field, html)
    slug = (field["property_slug"] || field["id"]).to_s
    return html unless declared_input_slugs.include?(slug)

    %(<% unless page_input_bound?(#{rb_str(slug)}) %>#{html}<% end %>)
  end

  def declared_input_slugs
    @declared_input_slugs ||= begin
      settings = page.configuration_json["form_settings"]
      settings.is_a?(Hash) ? Array(settings["inputs"]).grep(Hash).map { |input| input["field"].to_s } : []
    end
  end

  def field_boundary
    @field_boundary ||= Pages::FormParams.new(page: page, entity: page.entity, params: {}, audience: runtime_audience)
  end

  # Emits `<%= render ComponentClass.new(kwarg1: val1, ...) %>` ERB with
  # safely-serialized kwargs; ALWAYS appends the theme kwarg so every component
  # is themed at runtime via @page.configuration_json["theme"].
  #
  # kwargs values are expected to be pre-serialized Ruby source strings, e.g.:
  #   rb_str(user_value)        — user-supplied string, safe via String#inspect
  #   '"sm"'                    — whitelisted enum literal
  #   '42'                      — integer literal
  #   'true' / 'false'          — boolean literal
  #   'some_variable'           — a Ruby variable reference (raw, trust only for
  #                               generator-controlled values, not user data)
  #
  # When block: is given (a String of ERB content), the output uses
  #   `do %> ... <% end` form instead of a self-closing `%>`.
  #
  # Theme is always appended as `theme: (@page.configuration_json["theme"] || {})`
  # unconditionally — components default theme to {}, so blank themes are fine.
  #
  # @param component_class [String] e.g. "FormFields::TextFieldComponent"
  # @param kwargs [Hash{Symbol => String}] kwarg name => pre-serialized Ruby source
  # @param block [String, nil] ERB block body (indented); nil for no block
  # @return [String] ERB source fragment
  def render_component_erb(component_class, kwargs = {}, block: nil)
    theme_src = '@page.configuration_json["theme"] || {}'
    all_pairs = kwargs.map { |k, v| "#{k}: #{v}" }
    all_pairs << "theme: (#{theme_src})"

    if block.nil?
      "<%= render #{component_class}.new(\n" \
        "        #{all_pairs.join(",\n        ")}\n" \
        "      ) %>"
    else
      "<%= render #{component_class}.new(\n" \
        "        #{all_pairs.join(",\n        ")}\n" \
        "      ) do %>\n" \
        "      #{block}\n" \
        "    <% end %>"
    end
  end

  # Render an arbitrary (possibly user-supplied) value as a safe Ruby string
  # literal for interpolation into generated ERB source. `String#inspect`
  # handles Ruby quoting/interpolation; rb_literal also neutralizes ERB tokens.
  # The receiving ViewComponent HTML-escapes the value on output, so values must
  # be passed raw here (NOT pre-`html_escape`d) to avoid double-escaping.
  def rb_str(value)
    rb_literal(value.to_s)
  end

  # ERB tokenizes before Ruby parses its literals; String#inspect alone does
  # not protect an embedded %> terminator. Keep delimiters out of source.
  def rb_literal(value)
    # Escape delimiters without rewriting Ruby's hashrocket syntax (=>).
    value.inspect.gsub("<") { '\\u003c' }.gsub("%>") { '%\\u003e' }
  end

  def wrap_with_runtime_controller(content)
    rules = page.configuration_json["rules"] || []
    calculations = page.configuration_json["calculations"] || []

    rules_json = ERB::Util.html_escape(rules.to_json)
    calcs_json = ERB::Util.html_escape(calculations.to_json)

    <<~HTML.strip
      <div data-controller="condition-runtime"
           data-condition-runtime-rules-value="#{rules_json}"
           data-condition-runtime-calculations-value="#{calcs_json}">
        #{content}
      </div>
    HTML
  end

  def resolve_dynamic_options(fields)
    DynamicOptionsResolver.new(tenant_customer_id, audience: runtime_audience).resolve(fields)
  end

  def runtime_audience
    EntityAttributeAudience.for_user(Current.user, customer_id: tenant_customer_id)
  end

  # Shared pages store customer_id NULL. Entry/option queries must use the
  # viewing tenant (Current.customer) so QueryBuilder is not called with nil.
  def tenant_customer_id
    Current.customer_id || page.customer_id
  end

  def generate_composite
    modules_config = page.configuration_json["modules"] || []
    return "" if modules_config.empty?

    renderer      = CompositePageRenderer.new(modules_config, customer_id: tenant_customer_id, audience: runtime_audience)
    modules_data  = renderer.render_modules
    tile_renderer = CompositeRenderer.new

    lines = []
    lines << '<div data-controller="composite-page" class="grid grid-cols-12 gap-4">'
    modules_data.each { |mod| lines << tile_renderer.render_module(mod) }
    lines << "</div>"
    lines.join("\n")
  end
end
