# frozen_string_literal: true

module FeatureModules
  # The framework entry step of a page → module handoff: one input per
  # user_fillable field of the module's input contract, pre-filled from the
  # invocation, submitted to FeatureModules::HandoffsController#update.
  #
  # Copy resolves under the module's i18n_scope (registration
  # `handoff_entry_i18n_scope`): `title`, `subtitle`, `continue` fall back to
  # the generic feature_modules.handoff_entry keys; every field needs
  # `fields.<name>.label` (and optionally `fields.<name>.placeholder`).
  #
  # The form leaves Turbo Drive so the module's entry_path is entered with a
  # top-level navigation.
  class HandoffEntryComponent < ApplicationComponent
    GENERIC_SCOPE = "feature_modules.handoff_entry"

    def initialize(fields:, submit_url:, i18n_scope:, values: {}, errors: nil)
      @fields     = Array(fields)
      @submit_url = submit_url
      @i18n_scope = i18n_scope
      @values     = (values || {}).to_h.with_indifferent_access
      @errors     = errors
    end

    attr_reader :fields, :submit_url, :errors

    def title    = copy(:title)
    def subtitle = copy(:subtitle)
    def continue_label = copy(:continue)

    def label_for(field)
      t("#{@i18n_scope}.fields.#{field.name}.label")
    end

    def placeholder_for(field)
      t("#{@i18n_scope}.fields.#{field.name}.placeholder", default: "")
    end

    def input_id(field) = "handoff_#{field.name}"
    def input_name(field) = "handoff[#{field.name}]"

    # How the field renders, from its declared contract type.
    def control_for(field)
      return :select if field.allowed_values.present?

      case field.type
      when "integer", "number" then :number
      when "email"             then :email
      when "boolean"           then :checkbox
      when "datetime"          then :datetime
      else :textarea
      end
    end

    def value_for(field)
      value = @values[field.name]
      control_for(field) == :datetime ? datetime_local(value) : value
    end

    def checked?(field)
      ActiveModel::Type::Boolean.new.cast(@values[field.name]) == true
    end

    def number_step(field)
      field.type == "integer" ? 1 : "any"
    end

    private

    def copy(key)
      t("#{@i18n_scope}.#{key}", default: t("#{GENERIC_SCOPE}.#{key}"))
    end

    def datetime_local(value)
      return if value.blank?

      time = value.respond_to?(:strftime) ? value : Time.zone.parse(value.to_s)
      time&.strftime("%Y-%m-%dT%H:%M")
    rescue ArgumentError
      nil
    end
  end
end
