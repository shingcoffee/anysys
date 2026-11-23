# frozen_string_literal: true

# Platform catalog (same justification as billing_plans): owned by the
# platform, not a tenant — no customer_id. CUD only via
# /81721200/admin/maintenance/platform/announcements.
class PlatformAnnouncement < ApplicationRecord
  SEVERITIES = %w[info warning critical].freeze
  STATUSES   = %w[draft published].freeze
  AUDIENCES  = %w[all selected].freeze

  validate :selected_audience_is_valid

  has_many :dismissals,
           class_name:  "PlatformAnnouncementDismissal",
           foreign_key: :platform_announcement_id,
           inverse_of:  :announcement,
           dependent:   :delete_all

  has_many :reads,
           class_name:  "PlatformAnnouncementRead",
           foreign_key: :platform_announcement_id,
           inverse_of:  :announcement,
           dependent:   :delete_all

  scope :published,    -> { where(status: "published") }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :kept,         -> { where(deleted_at: nil) }

  scope :within_window, ->(now = Time.current) {
    where(arel_table[:starts_at].eq(nil).or(arel_table[:starts_at].lteq(now)))
      .where(arel_table[:ends_at].eq(nil).or(arel_table[:ends_at].gt(now)))
  }

  scope :live, ->(now = Time.current) { kept.published.within_window(now) }

  scope :dismissed_by, ->(user_id, customer_id) {
    where(id: PlatformAnnouncementDismissal.where(user_id: user_id, customer_id: customer_id)
                                           .select(:platform_announcement_id))
  }

  def all_customers? = audience == "all"

  def segmented? = audience == "selected"

  def live?(now: Time.current)
    deleted_at.blank? &&
      status == "published" &&
      (starts_at.nil? || starts_at <= now) &&
      (ends_at.nil? || ends_at > now)
  end

  def scheduled?(now: Time.current)
    status == "published" && starts_at.present? && starts_at > now
  end

  def ended?(now: Time.current)
    status == "published" && ends_at.present? && ends_at <= now
  end

  # :draft | :scheduled | :live | :ended — single source of truth for the
  # lifecycle badge so views never re-derive it.
  def lifecycle(now: Time.current)
    return :draft unless status == "published"
    return :scheduled if scheduled?(now: now)
    return :ended if ended?(now: now)

    :live
  end

  def targeted_at?(customer_id)
    return true if all_customers?

    PlatformAnnouncements::CustomerQuery.matches?(customer_id: customer_id, rules: target_rules)
  end

  def matching_customers
    return Customer.none unless segmented?

    PlatformAnnouncements::CustomerQuery.call(rules: target_rules).order(:name, :id)
  end

  def body_for(locale)
    locale.to_s.start_with?("zh") ? body_zh : body_en
  end

  # Soft-delete live/ended/previously-live rows so 7-day inbox history
  # survives owner delete. Never-live drafts and scheduled rows hard-destroy.
  def discard_or_destroy!
    if live? || ended? || left_live_at.present?
      stamp = ended? ? ends_at : Time.current
      update!(deleted_at: Time.current, left_live_at: left_live_at || stamp)
    else
      destroy!
    end
  end

  private

  def selected_audience_is_valid
    return unless segmented?

    rules = PlatformAnnouncements::TargetRules.parse(target_rules)
    if rules.malformed?
      errors.add(:base, I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
    elsif !rules.usable?
      errors.add(:base, I18n.t("maint_platform.announcements.form.errors.target_rules_blank"))
    end
  end
end
