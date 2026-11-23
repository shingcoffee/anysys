# frozen_string_literal: true

class Flowchart < ApplicationRecord
  include SoftDeletable
  include JsonSerializable
  include TenantScoped
  include SharedIdentity
  include Versionable
  include Flowchart::ConfigurationAccessors
  include Flowchart::TemplateBuilder

  # Configuration
  soft_deletable deleted_status: :deleted
  # SoftDeletable restores to its `soft_delete_active_status` (default :active),
  # but a flowchart's enum has no :active — its non-deleted default is :draft.
  # Override so #restore brings a trashed flowchart back as a draft.
  def self.soft_delete_active_status = :draft
  # Configuration body: virtual attribute backed by the head version's content
  # (declared as a Rails attribute, not a DB column, so dirty-tracking and
  # json_attribute keep working after the column is dropped).
  attribute :configuration, :string
  json_attribute :configuration
  # customer_id is required for tenant-owned flowcharts
  # customer_id is NULL for platform Shared Resources

  # Status enum for soft delete
  enum :status, { launched: 0, deleted: 1, draft: 2 }, default: :draft

  # Versioning (Versionable concern handles has_many + belongs_to current_version)
  acts_as_versionable reflection: :flowchart_versions,
                      version_class: "FlowchartVersion",
                      content_class: "FlowchartConfigurationContent",
                      snapshot: :configuration,
                      customer_head_reflection: :flowchart_customer_heads

  # The version live submissions run while launched. Later saves land on a
  # draft version above it until the next launch publishes the head.
  belongs_to :launched_version, class_name: "FlowchartVersion", optional: true

  after_find :reload_definition_from_head!

  # Assistant persist always writes a new version, and it goes live at once
  # when the flowchart is launched.
  attr_accessor :assistant_version_write

  # Populate the virtual configuration from the current head content.
  def reload_definition_from_head!
    payload = resolved_current_version&.content&.payload
    if payload.present?
      self.configuration = payload
      remove_instance_variable(:@configuration_json) if instance_variable_defined?(:@configuration_json)
    end
    clear_changes_information if persisted?
    self
  end

  # The pages whose submissions this flowchart processes. The entity it works
  # on is the submitting page's, supplied at runtime as ctx[:bound_entity].
  has_many :pages, dependent: nil

  # Callbacks
  after_initialize :set_draft_status_for_new_records
  before_validation :generate_uuid, on: :create
  before_save :generate_activity
  # Runs after Versionable's auto-commit, so the head is the saved version.
  after_save :pin_launched_version
  # Ahead of the versions' dependent destroy, which the FK would block.
  before_destroy :release_launched_version, prepend: true

  # Validations
  validates :name, presence: true,
                   length: { minimum: 1, maximum: 100 }
  validates :name, uniqueness: { scope: :customer_id }, if: :customer_owned?
  validates :name, uniqueness: { conditions: -> { where(customer_id: nil) } }, if: :shared?
  validates :uuid, presence: true
  validates :uuid, uniqueness: { scope: :customer_id }, if: :customer_owned?
  validates :uuid, uniqueness: true, if: :shared?
  validates :configuration, presence: true
  validate :configuration_must_be_valid_json
  validate :configuration_must_have_required_structure
  validate :name_kept_while_launched, on: :update
  validate :pages_keep_their_processing, on: :update, if: :will_save_change_to_status?

  # Scopes
  # Override visible from SoftDeletable to show both draft and launched (exclude only deleted)
  scope :visible, -> { where(status: [:draft, :launched]) }
  # Tenant-owned first, then platform Shared Resources, then most recently updated
  scope :recent, -> { order(Arel.sql("customer_id IS NULL ASC"), updated_at: :desc) }
  scope :by_name, -> { order(:name) }
  scope :except_id, ->(id) { where.not(id: id) }
  scope :referenceable, -> { where(status: :launched) }

  # Default scope to show draft and launched flowcharts (exclude deleted)
  default_scope { visible }

  def initialize(attributes = nil)
    # Track if status was explicitly provided in initialization
    @status_explicitly_provided = attributes.is_a?(Hash) && (
      attributes.key?("status") || attributes.key?(:status)
    )
    super
  end

  # Publish the head: live submissions run it from now on.
  def launch!
    update!(status: :launched, launched_version_id: current_version_id)
  end

  # A saved draft version sits above the launched one, waiting to go live.
  def pending_draft?
    launched? && launched_version_id.present? && launched_version_id != current_version_id
  end

  # The launched version, else the head of a flowchart that is not launched.
  # The compiled activity column is built from it.
  def published_version
    launched_version || current_version
  end

  # The version live submissions run on the request's line: a tenant's
  # override head, else the published version.
  def live_version(cid = Current.customer_id)
    override_customer_id(cid) ? resolved_current_version(cid) : published_version
  end

  private

  # A save revises the newest version unless it is launched: a save forks a
  # draft from the launched version, or from an older version made the head,
  # then keeps revising that draft. Override lines and assistant writes commit
  # a version per save.
  def revise_head_in_place?(head, line_cid)
    line_cid.nil? && head.id != launched_version_id && !assistant_version_write &&
      !versions_for_owner(customer_id).exists?(version_number: (head.version_number + 1)..)
  end

  def retained_version_ids
    [launched_version_id].compact
  end

  # The edit lands on a draft version while the launched one stays live, so
  # the compiled activity must stay the launched one.
  def staging_draft?
    launched? && launched_version_id.present? && !will_save_change_to_launched_version_id? && !assistant_version_write
  end

  # Launching (or an assistant write) publishes the head; anything not
  # launched has no launched version.
  def pin_launched_version
    pinned =
      if !launched? then nil
      elsif launched_version_id.nil? || assistant_version_write then current_version_id
      else launched_version_id
      end
    update_column(:launched_version_id, pinned) unless pinned == launched_version_id
  end

  def release_launched_version
    update_column(:launched_version_id, nil) if launched_version_id.present?
  end

  # Parents call a subflow by a class name derived from its name, and the
  # launched activity keeps the name it was compiled with.
  def name_kept_while_launched
    return unless launched? && will_save_change_to_name? && override_customer_id.blank?

    errors.add(:name, I18n.t("maint_core.errors.validations.flowchart_rename_launched"))
  end

  def configuration_must_be_valid_json
    return if configuration.blank?

    JSON.parse(configuration)
  rescue JSON::ParserError => e
    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_invalid_json", message: e.message))
  end

  def configuration_must_have_required_structure
    return if configuration.blank? || !configuration_json

    validate_required_keys
    validate_elements_structure
    validate_connections_structure
    validate_metadata_structure
  end

  def validate_required_keys
    required_keys = %w[elements connections metadata]
    missing_keys = required_keys - configuration_json.keys

    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_missing_keys", missing_keys: missing_keys.join(", "))) if missing_keys.any?
  end

  def validate_elements_structure
    elements = configuration_json["elements"]
    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_elements_not_array")) if elements && !elements.is_a?(Array)
  end

  def validate_connections_structure
    connections = configuration_json["connections"]
    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_connections_not_array")) if connections && !connections.is_a?(Array)
  end

  def validate_metadata_structure
    metadata = configuration_json["metadata"]
    errors.add(:configuration, I18n.t("maint_core.errors.validations.configuration_metadata_not_object")) if metadata && !metadata.is_a?(Hash)
  end

  # A trashed flowchart would leave its pages unprocessable, and one taken
  # offline would stop its launched pages from accepting submissions.
  def pages_keep_their_processing
    return if launched?

    dependents = deleted? ? pages : pages.launched
    count = dependents.count
    return if count.zero?

    key = deleted? ? "flowchart_delete_used_by_pages" : "flowchart_offline_used_by_pages"
    errors.add(:base, I18n.t("maint_core.errors.validations.#{key}", count: count))
  end

  def generate_activity
    # `activity` is a compiled column on the parent row. A tenant override
    # must not overwrite the global default; runtime still reads this column.
    return if override_customer_id.present?
    return if staging_draft?

    self.activity = ActivityGenerator.new(self).generate
  rescue ActivityGenerator::Error => e
    # Invalid generator config must never wipe a prior activity or persist a
    # failure stub as activity source. Raise in test; elsewhere leave the
    # previous activity untouched so the configuration edit can still save.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator::Error: #{e.message}")
  rescue StandardError => e
    # Unexpected codegen bugs must never block save — otherwise the user loses
    # in-progress edits. Preserve the raise in test so we still catch
    # regressions; elsewhere annotate the activity field and move on.
    raise if Rails.env.test?

    Rails.logger.error("[Flowchart##{id || 'new'}] ActivityGenerator raised: #{e.class}: #{e.message}")
    self.activity = "# ActivityGenerator failed: #{e.class}: #{e.message}"
  end

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def set_draft_status_for_new_records
    return unless new_record?
    return if @status_explicitly_provided
    # Override the :launched status set by default_scope { visible }
    # The database default and enum default are both :draft
    self.status = :draft if launched?
  end
end
