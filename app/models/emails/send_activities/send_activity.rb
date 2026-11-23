# frozen_string_literal: true

module Emails
  module SendActivities
    class SendActivity < ApplicationRecord
      self.table_name = "email_send_activities"

      include TenantScoped

      STATUSES              = %w[pending processing cancelled failed succeed].freeze
      TERMINAL_STATUSES     = %w[succeed cancelled failed].freeze
      NON_TERMINAL_STATUSES = (STATUSES - TERMINAL_STATUSES).freeze
      # A `processing` campaign whose claim is older than this is treated as stalled
      # (worker crashed) and re-driven by the reaper.
      CLAIM_TTL = 30.minutes
      # A `processing` campaign still stuck this long after it first started sending is
      # treated as deterministically failing (e.g. a deleted template/list) and is
      # dead-lettered instead of re-driven forever. Comfortably larger than several
      # normal reclaim cycles so a genuinely-progressing large send is never failed.
      MAX_SENDING_AGE = 2.hours
      # Upper bound on lists a single send activity may target — enforced both
      # client-side (wizard) and here, so audience resolution never has to
      # silently truncate a runaway selection.
      MAX_EMAIL_LISTS = 10

      belongs_to :email_template, optional: false, class_name: "Emails::Template",
                                  foreign_key: :email_template_id
      has_many :send_activity_lists, class_name: "Emails::SendActivities::SendActivityList",
                                     foreign_key: :email_send_activity_id,
                                     inverse_of: :send_activity,
                                     dependent: :destroy,
                                     validate: true
      has_many :email_lists, through: :send_activity_lists, class_name: "Emails::Audience::List",
                             before_add: :assert_email_list_assignable!

      # Status → design-system badge variant, consumed by both the index
      # controller and the show view so the mapping can't diverge between them.
      STATUS_BADGE_VARIANTS = {
        "pending"    => :default,
        "processing" => :info,
        "succeed"    => :success,
        "cancelled"  => :danger,
        "failed"     => :danger
      }.freeze

      attr_accessor :recurrence_preset, :send_timing

      validates :customer_id, presence: true
      validates :name,        presence: true
      validates :status,      inclusion: { in: STATUSES }
      validates :email_template_id, presence: true
      validates :scheduled_at,      presence: true
      validate  :timezone_is_valid
      validate  :recurrence_rule_is_valid
      validate  :email_lists_presence_and_limit
      validate  :email_lists_same_tenant
      validate  :email_template_same_tenant
      before_destroy :guard_destroy_status!, prepend: true

      scope :due_for_send, -> { where(status: "pending").where("scheduled_at <= ?", Time.current) }
      scope :stalled_sending, ->(ttl: CLAIM_TTL) {
        where(status: "processing")
          .where("deferred_until IS NULL OR deferred_until <= ?", Time.current)
          .where("claimed_at IS NULL OR claimed_at <= ? OR (deferred_until IS NOT NULL AND claimed_at < deferred_until)", Time.current - ttl)
          .where("fanout_claim_token IS NULL OR fanout_claimed_at <= ?", Time.current - ttl)
      }

      def terminal? = TERMINAL_STATUSES.include?(status)

      def status_variant = STATUS_BADGE_VARIANTS.fetch(status, :default)

      def status_label
        return status.to_s unless STATUSES.include?(status)

        I18n.t("admin_modules.emails.send_activities.statuses.#{status}")
      end

      # Atomic claim used by the scheduler + reaper: only the worker whose
      # conditional UPDATE affects the row proceeds. Mirrors
      # Payments::Cron::ChargeDueSubscriptions#claim!, so two concurrent scheduler
      # ticks never double-send or double-create the next occurrence.
      def self.claim!(id)
        now = Time.current
        where(id: id, status: "pending")
          .update_all(status: "processing", started_at: now, claimed_at: now, progressed_at: now) == 1
      end

      # Reclaim a stalled `processing` campaign (still `processing`, stale claim).
      def self.reclaim_stalled!(id, ttl: CLAIM_TTL)
        stalled_sending(ttl: ttl).where(id: id)
          .update_all(claimed_at: Time.current) == 1
      end

      # Dead-letter a `processing` campaign still stuck past MAX_SENDING_AGE (measured
      # from started_at). Atomic conditional transition — same one-winner pattern as
      # .claim!/.reclaim_stalled! — so two overlapping reaper runs can neither
      # double-fail the row nor fail-then-re-enqueue it. Returns true iff THIS call
      # performed the transition. `campaign.stats` is merged in so the recorded
      # failure_reason is preserved alongside existing counters.
      def self.fail_stalled!(campaign, reason: nil, max_age: MAX_SENDING_AGE)
        where(id: campaign.id, status: "processing")
          .where(deferred_reason: nil)
          .where("COALESCE(progressed_at, started_at) IS NULL OR COALESCE(progressed_at, started_at) <= ?", Time.current - max_age)
          .update_all(status: "failed", stats: campaign.stats.merge("failure_reason" => reason.to_s)) == 1
      end

      # Atomic conditional transitions (mirror .claim!/.reclaim_stalled!):
      # only the caller whose conditional UPDATE affects the row transitions, so a
      # race can't resurrect a just-completed/cancelled campaign.
      # Each returns true iff THIS call performed the transition.

      def complete!(run_token: nil)
        scope = self.class.where(id: id, status: "processing")
        scope = scope.where(fanout_claim_token: run_token) if run_token
        transitioned = scope.update_all(status: "succeed", completed_at: Time.current,
                                        fanout_claim_token: nil, fanout_claimed_at: nil) == 1
        reload if transitioned
        transitioned
      end

      def cancel!
        transitioned = self.class.where(id: id, status: NON_TERMINAL_STATUSES)
                           .update_all(status: "cancelled", fanout_claim_token: nil, fanout_claimed_at: nil,
                                       deferred_until: nil, deferred_reason: nil) == 1
        reload if transitioned
        transitioned
      end

      # Keep the claim fresh across a batched send so the reaper doesn't reclaim
      # an actively-progressing campaign.
      def touch_claim!
        update_columns(claimed_at: Time.current)
      end

      def recurring? = recurrence_rule.present?

      def increment_stat!(key, by: 1)
        key_str = key.to_s
        with_lock do
          current_stats = stats || {}
          update!(stats: current_stats.merge(key_str => current_stats[key_str].to_i + by))
        end
      end

      # Real delivery metrics rolled up from the per-recipient Emails::Message
      # ledger (indexed via email_messages.email_send_activity_id), so delivered/bounced/
      # complained counts reflect reality rather than the queue-time sent_count.
      def delivery_counts
        Emails::Message.where(email_send_activity_id: id).group(:status).count
      end

      # Union of every associated list's audience, deduped by normalized email
      # (lowest user_id wins) so a recipient on multiple lists is only ever
      # counted/sent once. Deduping stays in SQL so large audiences are not
      # materialized into Ruby / a giant IN-list.
      def audience
        sql = audience_winner_ids_sql
        return Authentication::User.none unless sql

        Authentication::User.where("users.id IN (#{sql})").order(:id)
      end

      def audience_count
        sql = audience_winner_ids_sql
        return 0 unless sql

        Authentication::User.from("(#{sql}) AS audience_winners").count
      end

      private

      def guard_destroy_status!
        Emails::Quota.synchronize(customer) do
          reload
          unless %w[pending cancelled].include?(status)
            errors.add(:base, I18n.t("admin_modules.flash.send_activities.delete_status_blocked", status: status_label))
            throw :abort
          end
        end
      end

      def audience_winner_ids_sql
        parts = email_lists.filter_map do |list|
          list.audience
              .unscope(:select, :order)
              .where("TRIM(COALESCE(users.email, '')) <> ''")
              .select("users.id AS id", "LOWER(TRIM(users.email)) AS normalized_email")
              .to_sql
              .presence
        end
        return if parts.empty?

        "SELECT MIN(id) AS id FROM (#{parts.join(' UNION ')}) AS candidates GROUP BY normalized_email"
      end

      # Guard association writes (`<<` / `concat`) so max/tenant rules cannot be
      # bypassed without going through SendActivity#save validations. Assignment
      # replace (clear + re-add) still works because size is checked before each add.
      def assert_email_list_assignable!(list)
        if customer_id.present? && list.customer_id != customer_id
          raise ActiveRecord::RecordNotSaved, I18n.t("admin_modules.errors.validations.cross_tenant_association")
        end
        return if email_lists.size < MAX_EMAIL_LISTS

        raise ActiveRecord::RecordNotSaved,
              I18n.t("admin_modules.emails.send_activities.errors.lists_too_many", max: MAX_EMAIL_LISTS)
      end

      def timezone_is_valid
        return if timezone.blank?

        ActiveSupport::TimeZone.find_tzinfo(timezone)
      rescue TZInfo::InvalidTimezoneIdentifier
        errors.add(:timezone, I18n.t("admin_modules.errors.validations.invalid_timezone"))
      end

      def recurrence_rule_is_valid
        return if recurrence_rule.blank?
        return if RecurrenceRule.valid?(recurrence_rule)

        errors.add(:recurrence_rule, I18n.t("admin_modules.errors.validations.invalid_recurrence_rule"))
      end

      def email_lists_presence_and_limit
        count = email_lists.size
        if count.zero?
          errors.add(:email_lists, I18n.t("admin_modules.emails.send_activities.errors.lists_blank"))
        elsif count > MAX_EMAIL_LISTS
          errors.add(:email_lists, I18n.t("admin_modules.emails.send_activities.errors.lists_too_many", max: MAX_EMAIL_LISTS))
        end
      end

      # Cross-tenant guard (C-SEC-1): both associations validate customer_id
      # presence, so there is no NULL-customer (shared) row to special-case —
      # strict equality is correct.
      def email_lists_same_tenant
        return if customer_id.nil?

        email_lists.each do |list|
          next if list.customer_id == customer_id

          errors.add(:email_lists, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
          break
        end
      end

      def email_template_same_tenant
        return if email_template.nil? || customer_id.nil? || email_template.customer_id == customer_id

        errors.add(:email_template_id, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
      end
    end
  end
end
