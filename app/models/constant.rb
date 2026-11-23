class Constant < ApplicationRecord
  include SharedIdentity

  # Associations
  belongs_to :customer, optional: true
  has_many :constant_customer_overrides, dependent: :destroy

  # Callbacks
  before_validation :ensure_options_is_array
  before_validation :restore_shared_identity!, if: :writing_customer_override?
  after_find :reload_options_from_override!
  before_save :stash_customer_override!, if: :writing_customer_override?
  after_save :persist_stashed_override!, if: :writing_customer_override?

  # Validations
  validates :name, presence: true
  validates :name, uniqueness: { scope: :customer_id }, if: :customer_owned?
  validates :name, uniqueness: true, if: :shared?
  validates :options, presence: true
  validate :options_must_not_be_blank
  validate :options_must_be_unique

  # Scopes
  scope :ordered, -> { order(name: :asc) }

  def customer_override?(cid = Current.customer_id)
    override_for(cid).present?
  end

  def reset_customer_override!(cid = Current.customer_id)
    return false unless shared? && cid.present?

    ov = override_for(cid)
    return false unless ov

    ov.destroy
    reload_options_from_override!
    true
  end

  private

  def writing_customer_override?
    persisted? && override_customer_id.present?
  end

  def override_customer_id(cid = Current.customer_id)
    return nil unless shared?
    return nil if cid.blank? || Current.shared_resources_mode

    cid
  end

  def override_for(cid)
    return nil if cid.blank?

    rel = constant_customer_overrides
    if rel.loaded?
      rel.target.find { |ov| ov.customer_id == cid }
    else
      rel.find_by(customer_id: cid)
    end
  end

  def reload_options_from_override!
    cid = override_customer_id
    return if cid.blank?

    ov = override_for(cid)
    self.options = ov.options if ov
    clear_changes_information if persisted?
  end

  def restore_shared_identity!
    self.name = attribute_in_database("name")
  end

  def stash_customer_override!
    @stashed_override_options = options
    self.options = attribute_in_database("options")
  end

  def persist_stashed_override!
    return if @stashed_override_options.nil?

    incoming = Array(@stashed_override_options)
    # A tenant Save that matches the global default must not pin an override;
    # otherwise a no-op resubmit forks the customer off later global edits.
    if override_for(Current.customer_id).nil? && incoming == Array(options)
      self.options = incoming
      @stashed_override_options = nil
      return
    end

    constant_customer_overrides
      .find_or_initialize_by(customer_id: Current.customer_id)
      .update!(options: incoming)
    self.options = incoming
    @stashed_override_options = nil
  end

  def ensure_options_is_array
    self.options = [] if options.nil?
    self.options = [options] unless options.is_a?(Array)
  end

  def options_must_not_be_blank
    return if options.blank?

    cleaned_options = options.map(&:to_s).map(&:strip).reject(&:blank?)
    return if cleaned_options.any?

    errors.add(:options, I18n.t("maint_core.errors.validations.options_blank"))
  end

  def options_must_be_unique
    return if options.blank?

    cleaned_options = options.map(&:to_s).map(&:strip).reject(&:blank?)
    duplicates = cleaned_options.group_by { |o| o }.select { |_, v| v.size > 1 }.keys

    if duplicates.any?
      errors.add(:options, I18n.t("maint_core.errors.validations.options_must_be_unique", duplicates: duplicates.join(", ")))
    end
  end
end
