# frozen_string_literal: true

# RolePermission
#
# Stores a single grant: "for {role}, allow {action} on {subject}".
# Translated into a CanCan rule by Ability#apply_grant.
#
# Subject taxonomy (validated below):
#   Route       — subject_key required, subject_id forbidden
#   Module      — subject_key required, subject_id forbidden
#   FeaturePage — subject_key required, subject_id forbidden
#   Platform    — subject_key required, subject_id forbidden
#   EntityClass — subject_key required, subject_id forbidden  (collection grant)
#   PageClass   — subject_key required, subject_id forbidden  (collection grant)
#   Entity      — subject_id required, subject_key forbidden  (instance grant)
#   Page        — subject_id required, subject_key forbidden  (instance grant)
#
class RolePermission < ApplicationRecord
  belongs_to :role

  ACTIONS = %w[read create update destroy manage].freeze

  KEY_BASED_TYPES      = %w[Route Module FeaturePage Platform EntityClass PageClass].freeze
  INSTANCE_BASED_TYPES = %w[Entity Page].freeze
  SUBJECT_TYPES        = (KEY_BASED_TYPES + INSTANCE_BASED_TYPES).freeze

  validates :subject_type, presence: true, inclusion: { in: SUBJECT_TYPES }
  validates :action,       presence: true, inclusion: { in: ACTIONS }
  validate  :subject_shape_valid

  private

  # Enforces shape consistency between subject_type, subject_key, and subject_id
  # so that Ability#apply_grant always receives well-formed input.
  def subject_shape_valid
    return unless SUBJECT_TYPES.include?(subject_type)

    if KEY_BASED_TYPES.include?(subject_type)
      errors.add(:subject_key, I18n.t("admin_settings.errors.validations.subject_required_for_type", subject_type: subject_type)) if subject_key.blank?
      errors.add(:subject_id,  I18n.t("admin_settings.errors.validations.subject_forbidden_for_type", subject_type: subject_type)) if subject_id.present?
    elsif INSTANCE_BASED_TYPES.include?(subject_type)
      errors.add(:subject_id,  I18n.t("admin_settings.errors.validations.subject_required_for_type", subject_type: subject_type)) if subject_id.blank?
      errors.add(:subject_key, I18n.t("admin_settings.errors.validations.subject_forbidden_for_type", subject_type: subject_type)) if subject_key.present?
    end
  end
end
