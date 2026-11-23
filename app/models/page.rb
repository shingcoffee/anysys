# frozen_string_literal: true

class Page < ApplicationRecord
  include SoftDeletable
  include JsonSerializable
  include TenantScoped
  include SharedIdentity
  include Versionable
  include PageVisibility
  include PageEntityBinding
  include PageProcessing
  include PageLaunchLifecycle
  include PageConfigurationHelpers

  # Versioning (Versionable concern handles has_many + belongs_to current_version)
  acts_as_versionable reflection: :page_versions,
                      version_class: "PageVersion",
                      content_class: "PageConfigurationContent",
                      snapshot: :configuration,
                      customer_head_reflection: :page_customer_heads

  after_find :reload_definition_from_head!

  belongs_to :entity_version, optional: true

  # ==========================================================================
  # Configuration
  # ==========================================================================

  soft_deletable deleted_status: :inactive
  # Configuration body: virtual attribute backed by the head version's content.
  attribute :configuration, :string
  json_attribute :configuration, default: { "fields" => [], "metadata" => {} }

  # Populate the virtual configuration from the current head content, clearing
  # this model's own parsed-config memo so a reload re-parses fresh.
  def reload_definition_from_head!
    payload = resolved_current_version&.content&.payload
    if payload.present?
      self.configuration = payload
      remove_instance_variable(:@configuration_json_parsed) if instance_variable_defined?(:@configuration_json_parsed)
    end
    clear_changes_information if persisted?
    self
  end

  # ==========================================================================
  # JSON Configuration Override - Migration Support
  # ==========================================================================

  # Override the JsonSerializable configuration_json to ensure rules/calculations defaults.
  def configuration_json
    ivar = :@configuration_json_parsed
    return instance_variable_get(ivar) if instance_variable_defined?(ivar) && instance_variable_get(ivar)

    return nil if configuration.blank?

    begin
      config = JSON.parse(configuration)
      raise TypeError unless config.is_a?(Hash)

      config["rules"] ||= []
      config["calculations"] ||= []
      instance_variable_set(ivar, config)
    rescue JSON::ParserError, TypeError
      instance_variable_set(ivar, { "pages" => [], "metadata" => {} })
    end
  end

  # Both setters clear the parsed cache, so validations read what is saved.
  def configuration=(value)
    super
    remove_instance_variable(:@configuration_json_parsed) if instance_variable_defined?(:@configuration_json_parsed)
  end

  def configuration_json=(value)
    self.configuration = value.to_json
  end

  # Drop the parsed-config memo on reload. The JsonSerializable concern only
  # clears `@configuration_json`, but this model memoizes into
  # `@configuration_json_parsed`, so without this a reloaded record would keep
  # returning the pre-reload configuration.
  def reload(*)
    remove_instance_variable(:@configuration_json_parsed) if instance_variable_defined?(:@configuration_json_parsed)
    result = super
    reload_definition_from_head!
    remove_instance_variable(:@configuration_json_parsed) if instance_variable_defined?(:@configuration_json_parsed)
    result
  end

  # ==========================================================================
  # Enums
  # ==========================================================================

  enum :status, { active: 0, inactive: 1 }, default: :active

  # ==========================================================================
  # Validations
  # ==========================================================================

  validates :name,
            presence: true,
            length: { minimum: 1, maximum: 100 }

  validate :shared_page_binds_shared_entity

  validates :configuration, length: { maximum: 2.megabytes, message: ->(*) { I18n.t("maint_core.errors.validations.configuration_exceeds_limit") } }, allow_blank: true

  validate :configuration_must_be_valid_json
  validate :configuration_must_have_required_structure
  validate :entity_id_must_be_present
  validate :form_settings_are_valid
  validate :configuration_is_well_formed
  validate :live_bridge_audiences_hold, if: :live_inputs_changed?

  # ==========================================================================
  # Scopes
  # ==========================================================================

  scope :by_name,       -> { order(:name) }
  scope :recent,        -> { order(updated_at: :desc) }
  scope :launched,      -> { where(launched: true) }
  scope :search_by_name, ->(query) {
    return all if query.blank?
    where("LOWER(name) LIKE ?", "%#{query.downcase}%")
  }
  # The configuration body now lives in the head version's content; entity
  # binding is read from page_configuration_contents.payload via the join.
  CONFIG_ENTITY_ID_SQL = "json_extract(page_configuration_contents.payload, '$.metadata.entity_id')"

  # Compared as text, so a binding stored as a JSON number or string matches.
  scope :for_entity, ->(entity_id) {
    return none if entity_id.blank?
    joins(current_version: :content).where("CAST(#{CONFIG_ENTITY_ID_SQL} AS TEXT) = ?", entity_id.to_s)
  }
  # Pages whose head declares a locked input taking a record of this entity.
  scope :with_input_for_entity, ->(entity_id) {
    joins(current_version: :content).where(
      "EXISTS (SELECT 1 FROM json_each(page_configuration_contents.payload, '$.form_settings.inputs') " \
      "WHERE CAST(json_extract(json_each.value, '$.entity_id') AS TEXT) = ?)", entity_id.to_s
    )
  }
  # Live page generated from any version on this entity's current line.
  scope :generated_from_entity_line, ->(customer_id, entity) {
    owner = customer_id.nil? ? where(customer_id: nil) : where(customer_id: customer_id)
    owner.where(entity_version_id: entity.current_line_versions.select(:id))
  }
  # Pages whose metadata.entity_id is blank/null or not in Entity.for_customer.
  scope :uncategorized_for, ->(customer_id) {
    known = Entity.where(customer_id: customer_id).or(Entity.shared).select(:id)
    where(customer_id: customer_id).or(where(customer_id: nil))
      .joins(current_version: :content)
      .where(
        "#{CONFIG_ENTITY_ID_SQL} IS NULL OR CAST(#{CONFIG_ENTITY_ID_SQL} AS TEXT) = '' OR " \
        "#{CONFIG_ENTITY_ID_SQL} NOT IN (#{known.to_sql})"
      )
  }
  default_scope { visible }

  before_create :assign_public_uuid

  private

  def assign_public_uuid
    self.public_uuid ||= SecureRandom.uuid
  end

  def shared_page_binds_shared_entity
    return unless shared?
    return if entity_id.blank?

    return if Entity.shared.exists?(id: entity_id)

    errors.add(:entity_id, I18n.t("maint_core.errors.validations.shared_page_entity_must_be_shared"))
  end

  # ==========================================================================
  # Validation Helpers
  # ==========================================================================

  def entity_id_must_be_present
    return if entity_id.present?

    errors.add(:entity_id, I18n.t("maint_core.errors.validations.entity_id_must_be_selected"))
  end

  def configuration_must_be_valid_json
    return if configuration.blank?

    unless configuration.is_a?(String)
      errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_must_be_json_string"))
      return
    end

    parsed = JSON.parse(configuration)
    unless parsed.is_a?(Hash)
      errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_must_be_object"))
    end
  rescue JSON::ParserError, TypeError => e
    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_invalid_json", message: e.message))
  end

  def configuration_must_have_required_structure
    return if configuration.blank? || !configuration_json

    validate_required_keys
    validate_fields_structure
    validate_metadata_structure
  end

  def validate_required_keys
    config = configuration_json

    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_missing_pages_key")) unless config.key?("pages")
    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_missing_metadata_key")) unless config.key?("metadata")
  end

  def validate_fields_structure
    pages = configuration_json["pages"]
    return unless pages

    unless pages.is_a?(Array)
      errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_pages_not_array"))
      return
    end

    pages.each_with_index do |page, idx|
      errors.add(:configuration, I18n.t("maint_core.errors.validations.page_must_be_object", index: idx + 1)) unless page.is_a?(Hash)
      errors.add(:configuration, I18n.t("maint_core.errors.validations.page_fields_must_be_array", index: idx + 1)) if page.is_a?(Hash) && page["fields"] && !page["fields"].is_a?(Array)
    end
  end

  def validate_metadata_structure
    metadata = configuration_json["metadata"]
    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_metadata_not_object")) if metadata && !metadata.is_a?(Hash)
  end

  def form_settings_are_valid
    settings = configuration_json&.dig("form_settings")
    return unless settings.is_a?(Hash)

    if settings.key?("modes")
      modes = Array(settings["modes"]).map(&:to_s)
      if modes.empty?
        errors.add(:base, I18n.t("maint_core.errors.validations.page_modes_blank"))
      elsif (modes - SUBMISSION_MODES).any?
        errors.add(:base, I18n.t("maint_core.errors.validations.page_modes_invalid"))
      end
    end

    page_inputs.reject { |input| locked_input_references_entity?(input) }.each do |input|
      errors.add(:base, I18n.t("maint_core.errors.validations.page_input_invalid", field: input["field"]))
    end
  end

  # Must agree with Pages::InputBindings, which re-checks every input at runtime.
  def locked_input_references_entity?(input)
    attribute = Array(entity&.property_schema_json).grep(Hash).find { |item| item["name_slug"] == input["field"] }
    attribute.present? && Entities::BridgeParticipants.referenced_entity_id(attribute) == input["entity_id"]
  end

  # Launch checks the audiences, and the visibility contract re-checks them;
  # an edit to a live page's locked inputs is the remaining way to break the
  # owned-link rule.
  def live_inputs_changed?
    return false unless persisted? && launched? && attribute_in_database(:launched) && will_save_change_to_configuration?

    stored = begin
      JSON.parse(attribute_in_database(:configuration).to_s)
    rescue JSON::ParserError
      {}
    end
    stored_inputs = stored.is_a?(Hash) ? Array(stored.dig("form_settings", "inputs")).grep(Hash).map { |input| input["field"].to_s } : []
    stored_inputs.sort != input_slugs.sort
  end

  def live_bridge_audiences_hold
    Pages::LaunchChecks.new(self).bridge_member_only_errors.each { |message| errors.add(:base, message) }
  end

  def configuration_is_well_formed
    return if configuration.blank?

    begin
      parsed = JSON.parse(configuration)
    rescue JSON::ParserError, TypeError
      # configuration_must_be_valid_json already adds the appropriate error
      # (invalid JSON, or "must be a JSON string" for non-String input); skip here
      return
    end

    validator = Pages::ConfigurationValidator.new(parsed)
    return if validator.valid?

    validator.errors.each { |msg| errors.add(:configuration, msg) }
  end
end
