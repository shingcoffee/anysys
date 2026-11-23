# frozen_string_literal: true

require "digest"
require "json"

module Sms
  # Request identity deliberately excludes resolved provider/template settings:
  # a genuine replay still works after retirement, reassignment or disablement.
  class MessageAdmission
    DEFAULT_LIFETIME = 1.hour
    MAX_KEY_BYTES = SendStandards::MAX_KEY_BYTES

    attr_reader :to, :template_key, :vars, :idempotency_key, :mode, :provider, :expires_at, :fingerprint

    def initialize(to:, template_key:, vars:, idempotency_key: nil, mode: nil, provider: nil, expires_at: nil)
      @to = PhoneNumber.normalize(to)
      input_vars = vars.nil? ? {} : vars
      errors = SendStandards.validation_errors(to: @to, template_key: template_key, vars: input_vars,
                                               idempotency_key: idempotency_key)
      unless errors.empty?
        invalid!("recipient_invalid") if errors.key?(:to)
        raise Errors::TemplateVarsInvalid, errors.values.to_sentence
      end
      @template_key = template_key.dup
      @idempotency_key = idempotency_key&.presence&.dup
      @mode = selection(mode)
      @provider = selection(provider)
      @vars = canonical_vars(input_vars)
      unless expires_at.nil? || expires_at.is_a?(Time) || expires_at.is_a?(ActiveSupport::TimeWithZone)
        invalid!("expiry_invalid")
      end
      @expires_at = expires_at
      @fingerprint = Digest::SHA256.hexdigest(JSON.generate(
        to: @to, template_key: @template_key, vars: @vars, provider: @provider, mode: @mode,
        expires_at: expires_at&.to_time&.getutc&.iso8601(6)
      ))
    end

    def self.existing(customer, key)
      return unless key

      Message.uncached { Message.find_by(customer_id: customer.id, idempotency_key: key) }
    end

    def self.for_campaign(customer:, recipient:)
      campaign = Campaign.find_by!(id: recipient.campaign_id, customer_id: customer.id)
      recipient = CampaignRecipient.find_by!(id: recipient.id, customer_id: customer.id, campaign_id: campaign.id)
      unless Campaigns::Snapshot.valid?(campaign) && campaign.status == "running" &&
        recipient.contact_snapshot.dig("eligibility_at_start", "eligible") == true &&
        recipient.phone_e164 == recipient.contact_snapshot["phone_e164"] &&
        %w[pending admitted].include?(recipient.status)
        raise Errors::TemplateVarsInvalid, I18n.t("sms.errors.snapshot_invalid")
      end
      settings = campaign.settings_snapshot
      pinned = settings.fetch("template")
      unless SendStandards.vars_valid?(recipient.vars) && recipient.vars.keys.sort == pinned.fetch("required_vars").sort
        raise Errors::TemplateVarsInvalid, I18n.t("sms.errors.snapshot_invalid")
      end
      request = new(to: recipient.phone_e164, template_key: pinned.fetch("key"), vars: recipient.vars,
        idempotency_key: "sms-campaign:#{campaign.id}:recipient:#{recipient.id}", provider: settings.fetch("provider"),
        mode: settings.fetch("credential_mode"), expires_at: campaign.expires_at)
      request.instance_variable_set(:@campaign_recipient, recipient)
      request.instance_variable_set(:@campaign, campaign)
      request.instance_variable_set(:@fingerprint, Digest::SHA256.hexdigest(JSON.generate(
        core: request.fingerprint, campaign_id: campaign.id, contact_id: recipient.contact_id, recipient_id: recipient.id)))
      request
    end

    def campaign? = @campaign_recipient.present?

    def campaign_template
      pinned = @campaign.settings_snapshot.fetch("template")
      Template.new(id: pinned.fetch("id"), key: pinned.fetch("key"), purpose: "marketing",
        variables: pinned.fetch("required_vars"), provider_template_codes: { provider => pinned.fetch("provider_code") })
    end

    def campaign_credential
      DeliveryCredential.for_campaign(@campaign)
    end

    def marketing_contact!(customer, template)
      return unless template.purpose == "marketing"
      contact = if campaign?
        Contact.find_by(customer_id: customer.id, id: @campaign_recipient.contact_id)
      else
        Contact.find_by(customer_id: customer.id, phone_e164: to)
      end
      contact&.lock!
      MarketingEligibility.require!(customer: customer, contact: contact, phone_e164: to)
    end

    def replay!(message)
      unless message.metadata["request_fingerprint"] == fingerprint
        raise Errors::IdempotencyConflict, I18n.t("sms.errors.idempotency_conflict")
      end
      message
    end

    def validate_template!
      contract = Contracts::Send.new(Contracts::Send::Input.new)
      unless contract.validate(to: to, template_key: template_key, vars: vars, idempotency_key: idempotency_key)
        raise Errors::TemplateVarsInvalid, contract.errors.full_messages.to_sentence
      end
      contract.template
    end

    def validate_provider!(template, credential)
      return if template.provider_code(credential.provider).present?

      raise Errors::TemplateVarsInvalid,
            I18n.t("admin_modules.sms.errors.provider_code_missing", provider: credential.provider)
    end

    def persist(customer:, template:, credential:, suppressed: false)
      Quota.synchronize(customer) do
        if campaign?
          @campaign = Campaign.find_by!(id: @campaign.id, customer_id: customer.id)
          @campaign.lock!
          Contact.find_by!(id: @campaign_recipient.contact_id, customer_id: customer.id).lock!
          @campaign_recipient = CampaignRecipient.find_by!(id: @campaign_recipient.id, campaign_id: @campaign.id, customer_id: customer.id)
          @campaign_recipient.lock!
          fresh = self.class.for_campaign(customer: customer, recipient: @campaign_recipient)
          unless fresh.fingerprint == fingerprint
            raise Errors::IdempotencyConflict, I18n.t("sms.errors.idempotency_conflict")
          end
          policy = Campaigns::DeliveryPolicy.call(message: Message.new(customer_id: customer.id, campaign_id: @campaign.id,
            contact_id: @campaign_recipient.contact_id, to: to, expires_at: expires_at,
            metadata: { "template_snapshot" => { "purpose" => "marketing" } }))
          raise Errors::MarketingIneligible.new(reason: policy[:reason]) unless policy[:action] == :allow
        end
        persist_locked(customer: customer, template: template, credential: credential, suppressed: suppressed)
      end
    end

    def persist_locked(customer:, template:, credential:, suppressed:)
      # Persistence is not a second, unguarded admission entry. Read actual
      # template/contact identity even if a caller passed a modified AR object.
      template = campaign? ? campaign_template : validate_template!
      contact = marketing_contact!(customer, template)
      if campaign?
        unless Campaigns::Snapshot.valid?(@campaign) && @campaign.expires_at > Time.current &&
          credential&.id == @campaign.settings_snapshot["credential_id"] && credential.provider == provider && credential.mode == mode
          raise Errors::TemplateVarsInvalid, I18n.t("sms.errors.snapshot_invalid")
        end
      end
      snapshot = {
        key: template_key, provider: credential&.provider, provider_code: credential && template.provider_code(credential.provider),
        required_vars: template.required_vars.map(&:to_s), vars: vars, purpose: template.purpose
      }
      message = Message.transaction(requires_new: true) do
        Message.create!(customer: customer, sms_template_id: template.id, to: to, template_key: template_key, vars: vars,
                        campaign_id: @campaign&.id, contact_id: contact&.id,
                        idempotency_key: idempotency_key, provider: credential&.provider,
                        status: suppressed ? "suppressed" : "queued", expires_at: expires_at || DEFAULT_LIFETIME.from_now,
                        metadata: (credential ? DeliveryCredential.metadata(credential) : {}).merge(
                          request_fingerprint: fingerprint, template_snapshot: snapshot
                        ))
      end
      [message, true]
    rescue ActiveRecord::RecordNotUnique
      existing = self.class.existing(customer, idempotency_key)
      raise unless existing

      [replay!(existing), false]
    end
    private :persist_locked

    private

    def selection(value)
      return nil if value.nil?
      invalid!("key_invalid") unless value.is_a?(String) || value.is_a?(Symbol)
      string = value.to_s
      invalid!("key_invalid") unless SendStandards.idempotency_key_valid?(string) && string.present?
      string.dup
    end

    def canonical_vars(input)
      # SendStandards has already bounded count, keys, scalar values and JSON
      # wire bytes and rejected duplicate normalized keys before any copying.
      # JSON round-trip gives the ledger and fingerprint the same scalar types
      # (including decimals); insertion order and symbol/string keys are neutral.
      JSON.parse(JSON.generate(input.transform_keys(&:to_s).sort.to_h))
    rescue JSON::GeneratorError, JSON::ParserError, EncodingError
      invalid!("vars_invalid")
    end

    def invalid!(key)
      raise Errors::TemplateVarsInvalid, I18n.t("sms.errors.#{key}")
    end
  end
end
