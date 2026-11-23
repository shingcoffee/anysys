# frozen_string_literal: true

class SearchableSelectComponent < ApplicationComponent
  attr_reader :name, :selected_value, :grouped_options, :field_id, :expand_all

  # @param name [String] form field name (e.g. "customer[industry]")
  # @param selected_value [String, nil] currently selected value
  # @param grouped_options [Array<[String, Array<[String, String]>]>] grouped options: [["Group", [["Label", "value"], ...]]]
  # @param placeholder [String] placeholder text for search input
  # @param field_id [String] HTML id for the component
  # @param expand_all [Boolean] when true, groups start expanded
  def initialize(name:, selected_value: nil, grouped_options: [], placeholder: nil, field_id: nil, expand_all: false)
    @name = name
    @selected_value = selected_value
    @grouped_options = grouped_options
    @placeholder = placeholder
    @field_id = field_id
    @expand_all = expand_all
  end

  # Resolved at render time (never at class-load) so the current locale wins.
  def placeholder
    @placeholder || I18n.t("chrome.searchable_select.placeholder")
  end

  def options_json
    grouped_options.map do |group_name, items|
      { group: group_name, items: items }
    end.to_json
  end

  def has_selection?
    selected_value.present?
  end
end
