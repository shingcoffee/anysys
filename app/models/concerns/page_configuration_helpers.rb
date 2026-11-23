# frozen_string_literal: true

# PageConfigurationHelpers
#
# Derived-data accessors and feature toggles that read from the page's
# configuration JSON blob.  None of these methods write to the database
# directly — they either return computed values or stage changes via
# configuration_json= (which callers must persist with save/update).
#
# Provides:
#   #fields              — flat list of all field hashes across all config pages
#   #input_fields        — every input field, columns flattened, layout dropped
#   #metadata            — the top-level metadata hash
#   #submission_modes    — the submissions (create / update) the page accepts
#   #serves?(action)     — true when the page accepts that submission
#   #page_inputs         — locked inputs: [{ "field" => slug, "entity_id" => id }]
#   #input_slugs         — the slugs of the locked inputs
#   #manages_rows?       — members manage the rows from their locked record
#   #success_message     — the page's own message after a submit (nil if unset)
#   #captcha_enabled?    — reads captcha.enabled from the config
#   #captcha_enabled=    — stages captcha.enabled in the config
#   #generate_content    — delegates to PageContentGenerator
#   #searchable_field_keys — model columns available for search
#   #sortable_field_keys   — model columns available for sorting
#
module PageConfigurationHelpers
  extend ActiveSupport::Concern

  SUBMISSION_MODES = %w[create update].freeze

  # Flat list of all field hashes across every page in the configuration.
  def fields
    config = configuration_json
    return [] unless config

    Array(config["pages"]).grep(Hash).flat_map { |p| Array(p["fields"]) }
  end

  # Every input field on every step: column layouts flattened, headings,
  # dividers and spacers dropped.
  def input_fields
    self.class.input_fields_in(configuration_json)
  end

  class_methods do
    # The same walk over a raw configuration hash, e.g. a tenant override's payload.
    def input_fields_in(config)
      return [] unless config.is_a?(Hash)

      collect_input_fields(Array(config["pages"]).grep(Hash).flat_map { |step| Array(step["fields"]) })
    end

    private

    def collect_input_fields(items)
      items.flat_map do |field|
        next [] unless field.is_a?(Hash)

        if field["field_type"] == "columns"
          collect_input_fields(Array(field["columns"]).grep(Hash).flat_map { |column| Array(column["fields"]) })
        elsif field["property_type"] == "layout"
          []
        else
          [field]
        end
      end
    end
  end

  # The top-level metadata hash from configuration.
  def metadata
    configuration_json&.dig("metadata") || {}
  end

  # Which submissions the page accepts; a page without a setting does both.
  def submission_modes
    modes = Array(configuration_json&.dig("form_settings", "modes")).map(&:to_s) & SUBMISSION_MODES
    modes.presence || SUBMISSION_MODES
  end

  def serves?(action) = submission_modes.include?(action.to_s)

  # Fields filled from the visitor's run instead of the form.
  def page_inputs
    Array(configuration_json&.dig("form_settings", "inputs")).grep(Hash).map do |input|
      input.slice("field", "entity_id").transform_values(&:to_s)
    end
  end

  def input_slugs = page_inputs.map { |input| input["field"] }

  # The page's audience adds, changes and removes its rows from the page of
  # the record its locked input names (Pages::MemberRows).
  def manages_rows? = configuration_json&.dig("form_settings", "manage_rows") == true

  # Display copy only: where the visitor goes next is the journey's call, and
  # a message the flowchart sets wins over this one.
  def success_message
    configuration_json&.dig("form_settings", "success_message").to_s.strip.presence
  end

  # Per-page captcha toggle.  Source of truth lives in
  # configuration_json["captcha"]["enabled"]; the JS page editor round-trips it
  # through this writer.  Vendor-agnostic: which provider actually renders is
  # decided by Captcha::ProviderSettings.active.
  def captcha_enabled?
    configuration_json&.dig("captcha", "enabled") == true
  end

  # Stage captcha.enabled in the configuration.  Callers must persist via save.
  def captcha_enabled=(value)
    config = configuration_json || self.class.send(:default_configuration)
    config["captcha"] = { "enabled" => ActiveModel::Type::Boolean.new.cast(value) == true }
    self.configuration_json = config
  end

  # Delegate ERB template generation to the dedicated generator service.
  def generate_content(presentation: :themed)
    PageContentGenerator.new(self, presentation: presentation).generate
  end

  # Model columns that the search layer may filter on.
  def searchable_field_keys
    %w[name description]
  end

  # Model columns that the sort layer may order by (superset of searchable).
  def sortable_field_keys
    searchable_field_keys + %w[created_at updated_at]
  end
end
