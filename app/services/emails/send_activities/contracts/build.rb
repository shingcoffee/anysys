# frozen_string_literal: true

module Emails
  module SendActivities
    module Contracts
      class Build < Reform::Form
        Input = Struct.new(:customer_id, :name, :email_template_id, :email_list_ids,
                           :scheduled_at, :timezone, :recurrence_rule)

        property :customer_id
        property :name
        property :email_template_id
        property :email_list_ids
        property :scheduled_at
        property :timezone
        property :recurrence_rule

        validates :name, :scheduled_at, :timezone, presence: true
        validate :template_is_active_and_accessible
        validate :lists_are_accessible_and_bounded
        validate :timezone_is_valid
        validate :recurrence_is_valid
        validate :delivery_supports_template

        def lists
          @lists || []
        end

        private

        def template_is_active_and_accessible
          return if Emails::Template.active.exists?(id: email_template_id, customer_id: customer_id)

          errors.add(:email_template_id, I18n.t("admin_modules.errors.validations.template_not_active"))
        end

        def lists_are_accessible_and_bounded
          values = Array(email_list_ids).reject(&:blank?)
          unless values.all? { |id| id.to_s.match?(/\A\d+\z/) }
            return errors.add(:email_lists, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
          end
          ids = values.map(&:to_i).uniq
          if ids.empty?
            return errors.add(:email_lists, I18n.t("admin_modules.emails.send_activities.errors.lists_blank"))
          end
          if ids.size > SendActivity::MAX_EMAIL_LISTS
            return errors.add(:email_lists, I18n.t("admin_modules.emails.send_activities.errors.lists_too_many", max: SendActivity::MAX_EMAIL_LISTS))
          end
          @lists = Emails::Audience::List.where(customer_id: customer_id, id: ids).to_a
          if @lists.size != ids.size
            return errors.add(:email_lists, I18n.t("admin_modules.errors.validations.cross_tenant_association"))
          end
          if @lists.any? { |list| list.dynamic? && !Audience::SegmentQuery.valid?(list.segment_rules) }
            errors.add(:email_lists, I18n.t("admin_modules.errors.lists.segment_malformed"))
          end
        end

        def timezone_is_valid
          return if timezone.blank?

          ActiveSupport::TimeZone.find_tzinfo(timezone)
        rescue TZInfo::InvalidTimezoneIdentifier, ArgumentError
          errors.add(:timezone, I18n.t("admin_modules.errors.validations.invalid_timezone"))
        end

        def recurrence_is_valid
          return if RecurrenceRule.valid?(recurrence_rule)

          errors.add(:recurrence_rule, I18n.t("admin_modules.errors.validations.invalid_recurrence_rule"))
        end

        def delivery_supports_template
          return unless errors.empty?

          template = Emails::Template.active.find_by(id: email_template_id, customer_id: customer_id)
          unless template
            return errors.add(:email_template_id, I18n.t("admin_modules.errors.validations.template_not_active"))
          end
          MessageAdmission.validate_campaign!(template: template)
        rescue Email::Errors::UnsupportedMessage => error
          errors.add(:base, error.message)
        rescue Email::Errors::CredentialsMissing
          errors.add(:base, I18n.t("admin_modules.flash.templates.credentials_missing"))
        end
      end
    end
  end
end
