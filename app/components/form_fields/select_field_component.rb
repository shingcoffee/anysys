# frozen_string_literal: true

module FormFields
  class SelectFieldComponent < BaseFieldComponent
    attr_reader :options, :include_blank, :multiple, :quick_add

    # +quick_add+ ({ url:, label:, title:, dialog: }) appends an "+ Add New"
    # option that opens the entity quick-add dialog matched by the +dialog+
    # selector; only single selects support it.
    def initialize(options: [], include_blank: true, multiple: false, quick_add: nil, **args)
      super(**args)
      @options = options
      @include_blank = include_blank
      @multiple = multiple
      @quick_add = quick_add unless multiple
    end

    private

    def field_type
      :select
    end

    def render_input
      attributes = input_attributes.except(:value).merge(multiple: multiple)
      attributes[:name] = "#{field_name.to_s.delete_suffix('[]')}[]" if multiple
      return content_tag(:select, option_tags, **attributes) unless quick_add

      select_data = { entity_quick_add_target: "select", action: "change->entity-quick-add#change" }
      content_tag :div, class: "contents", data: quick_add_data do
        content_tag(:select, option_tags, **merge_html_attributes(attributes, data: select_data))
      end
    end

    def quick_add_data
      {
        controller: "entity-quick-add",
        entity_quick_add_url_value: quick_add[:url],
        entity_quick_add_title_value: quick_add[:title],
        entity_quick_add_entity_quick_add_dialog_outlet: quick_add[:dialog]
      }
    end

    def option_tags
      choices = options.map { |option| option.is_a?(Array) ? option.first(2) : [option, option] }
      # The add-new option must never be the default, so a list with nothing
      # else to choose keeps its blank placeholder.
      blank = !multiple && (include_blank || (quick_add && choices.empty?))
      choices.unshift([placeholder || I18n.t("comp_form_fields.select.blank_option"), ""]) if blank

      selected = choices.map { |_, option_value| selected_value?(option_value) }
      selected[0] = false if blank

      tags = choices.each_with_index.map do |(label, option_value), index|
        content_tag(:option, label, value: option_value, selected: selected[index])
      end
      # Empty value: without JavaScript, choosing it submits a blank.
      tags << content_tag(:option, quick_add[:label], value: "", data: { quick_add_option: true }) if quick_add
      safe_join(tags)
    end

    def selected_value?(option_value)
      multiple ? Array(value).map(&:to_s).include?(option_value.to_s) : option_value.to_s == value.to_s
    end
  end
end
