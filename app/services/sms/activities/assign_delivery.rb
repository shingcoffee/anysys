# frozen_string_literal: true

module Sms
  module Activities
    # Sets the live SMS vendor per environment by flipping Sms::Credential#status.
    # At most one credential is active per mode so CredentialResolver has a
    # single winner. Does not create rows or edit secrets.
    class AssignDelivery
      Result = Struct.new(:success?, :errors, keyword_init: true)

      def self.call(sandbox_provider:, production_provider:)
        errors = []
        Sms::Credential.transaction do
          lock_credentials!
          errors.concat(assign_mode("sandbox", sandbox_provider.to_s))
          errors.concat(assign_mode("production", production_provider.to_s))
          raise ActiveRecord::Rollback if errors.any?
        end
        Result.new(success?: errors.empty?, errors: errors)
      end

      # Credential-card saves use the same assignment transaction as the vendor
      # selector. An invalid save must not leave the previous vendor disabled.
      def self.persist(record:)
        errors = []
        Sms::Credential.transaction do
          lock_credentials!
          disable_others!(record) if record.status == "active"
          unless record.save
            record.errors.add(:base, :invalid) if record.errors.empty?
            errors = record.errors.full_messages
          end
          raise ActiveRecord::Rollback if errors.any?
        end
        Result.new(success?: errors.empty?, errors: errors)
      rescue ActiveRecord::RecordInvalid => error
        Result.new(success?: false, errors: error.record.errors.full_messages)
      end

      def self.assign_mode(mode, provider)
        if provider.blank?
          Sms::Credential.where(mode: mode, status: "active").find_each do |credential|
            credential.update!(status: "disabled")
          end
          return []
        end

        credential = Sms::Credential.find_by(provider: provider, mode: mode)
        unless credential
          return [I18n.t("maint_platform.sms.platform_settings.errors.missing_credential",
                         provider: provider, mode: mode)]
        end

        disable_others!(credential)
        credential.update!(status: "active")
        []
      rescue ActiveRecord::RecordInvalid => e
        e.record.errors.full_messages
      end

      def self.disable_others!(credential)
        Sms::Credential.active.where(mode: credential.mode).where.not(id: credential.id).find_each do |other|
          other.update!(status: "disabled")
        end
      end

      def self.lock_credentials!
        Sms::Credential.order(:id).lock.load
      end
      private_class_method :assign_mode, :disable_others!, :lock_credentials!
    end
  end
end
