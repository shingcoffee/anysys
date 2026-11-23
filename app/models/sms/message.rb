# frozen_string_literal: true

module Sms
  # An SMS send record + delivery-status ledger. Status transitions are
  # monotonic: once a message reaches a terminal status it does not regress, and
  # `delivered` is the success floor (a late failure never overwrites it, but a
  # late delivery may repair a transient failure). This protects against
  # out-of-order delivery receipts and reconciliation queries.
  class Message < ApplicationRecord
    self.table_name = "sms_messages"

    include TenantScoped

    STATUSES          = %w[queued pending sent delivered failed unknown suppressed expired].freeze
    TERMINAL_STATUSES = %w[delivered failed suppressed expired].freeze
    FAILURE_DELIVERY     = "sms.failures.delivery_failed"
    FAILURE_UNCONFIRMED  = "sms.failures.send_never_confirmed"
    FAILURE_SEND         = "sms.failures.send_failed"

    belongs_to :sms_template, optional: true,
                              class_name: "Sms::Template",
                              foreign_key: :sms_template_id
    belongs_to :campaign, class_name: "Sms::Campaign", optional: true
    belongs_to :contact, class_name: "Sms::Contact", optional: true
    has_one :campaign_recipient, class_name: "Sms::CampaignRecipient", foreign_key: :message_id

    validates :to,           presence: true
    validates :template_key, presence: true
    validates :status,       inclusion: { in: STATUSES }
    validates :customer_id,  presence: true
    validates_with Sms::TenantReferences, attributes: %i[campaign contact]

    scope :non_terminal, -> { where.not(status: TERMINAL_STATUSES) }
    scope :delivery_due, ->(at = Time.current) { where("delivery_due_at IS NULL OR delivery_due_at <= ?", at) }

    def self.rate_limit_window(customer_id:, to:, since: 1.day.ago)
      where(customer_id: customer_id, to: to).where.not(status: "suppressed")
        .where(created_at: since..)
        .pluck(:created_at)
    end

    def terminal? = TERMINAL_STATUSES.include?(status)

    # API acceptance only; carrier delivery is recorded separately by receipts.
    def mark_sent!(vendor_message_id:, raw:, claim_token: nil, attempt_started_at: nil)
      transition!(from: %w[queued pending unknown], claim_token: claim_token, attempt_started_at: attempt_started_at,
                  status: "sent", vendor_message_id: vendor_message_id,
                  raw_response: raw, sent_at: Time.current)
      if attempt_started_at
        # A receipt can finish the known-ID attempt before a late API result.
        # Fill acceptance facts without overwriting carrier status/raw/failure.
        transition_scope(from: %w[sent delivered failed], claim_token: claim_token, attempt_started_at: attempt_started_at)
          .where(sent_at: nil, vendor_message_id: [nil, vendor_message_id])
          .update_all(sent_at: Time.current, vendor_message_id: vendor_message_id, updated_at: Time.current)
        reload
      end
      self
    end

    # Success floor — a late "delivered" repairs a transient failure, but a
    # message already delivered (or intentionally suppressed) is not touched.
    def mark_delivered!(at:, raw:, claim_token: nil)
      transition!(from: %w[pending sent unknown failed], claim_token: claim_token, status: "delivered", delivered_at: at,
                  raw_response: raw, failure_code: nil, failure_message: nil)
    end

    def mark_failed!(code:, message:, raw:, claim_token: nil, attempt_started_at: nil)
      transition!(from: %w[queued pending sent unknown], claim_token: claim_token, attempt_started_at: attempt_started_at,
                  status: "failed", failure_code: code,
                  failure_message: message, raw_response: raw)
    end

    def mark_unknown!(raw:, claim_token: nil, retain_claim: false, vendor_message_id: nil, attempt_started_at: nil)
      attributes = { status: "unknown", raw_response: raw }
      attributes[:vendor_message_id] = vendor_message_id if vendor_message_id.present?
      transition!(from: %w[queued pending sent unknown], claim_token: claim_token, retain_claim: retain_claim,
                  attempt_started_at: attempt_started_at, **attributes)
    end

    def mark_suppressed!(claim_token: nil)
      transition!(from: %w[queued pending unknown], claim_token: claim_token, unattempted: true, status: "suppressed")
    end

    def mark_expired!(claim_token: nil)
      transition!(from: %w[queued], claim_token: claim_token, unattempted: true, status: "expired")
    end

    # Canned failures are stored as I18n keys so a zh-CN admin UI does not
    # freeze the locale of the webhook/cron that wrote the row. Vendor text
    # is shown as-is.
    def displayed_failure_message
      return if failure_message.blank?
      return I18n.t(failure_message) if I18n.exists?(failure_message)

      failure_message
    end

    private

    def transition_scope(from:, claim_token:, unattempted: false, attempt_started_at: nil)
      scope = self.class.where(id: id, status: from)
      if attempt_started_at
        # Once attempted, the marker is immutable and no newer attempt can own
        # this row. Receipts may have cleared the sole attempt's token meanwhile.
        scope = scope.where(dispatch_started_at: attempt_started_at)
        scope = scope.where(delivery_claim_token: claim_token == :unclaimed ? nil : [nil, claim_token]) if claim_token
      elsif claim_token
        scope = scope.where(delivery_claim_token: claim_token == :unclaimed ? nil : claim_token)
      end
      scope = scope.where(dispatch_started_at: nil) if unattempted
      # A late query/receipt must not mutate a payload still being prepared.
      scope = scope.where("status != 'queued' OR dispatch_started_at IS NOT NULL") unless unattempted
      scope
    end

    def transition!(from:, claim_token: nil, unattempted: false, retain_claim: false, attempt_started_at: nil, **attributes)
      scope = transition_scope(from: from, claim_token: claim_token, unattempted: unattempted, attempt_started_at: attempt_started_at)
      if attempt_started_at
        scope = scope.where(sent_at: nil) if %w[sent unknown failed].include?(attributes[:status])
        scope = scope.where(vendor_message_id: [nil, attributes[:vendor_message_id]]) if attributes[:vendor_message_id].present?
      end
      attributes = attributes.merge(delivery_claim_token: nil, delivery_claimed_at: nil) unless retain_claim
      scope.update_all(attributes.merge(updated_at: Time.current))
      reload
      if campaign_id
        ActiveRecord.after_all_transactions_commit do
          begin
            Sms::Campaigns::RefreshStatsJob.perform_later(customer_id, campaign_id)
          rescue StandardError => error
            Rails.logger.warn("[sms.campaign.stats] campaign=#{campaign_id} #{error.class}")
          end
        end
      end
    end
  end
end
