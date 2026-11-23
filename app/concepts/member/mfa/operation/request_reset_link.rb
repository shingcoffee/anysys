# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class RequestResetLink
        Result = Struct.new(:success?, keyword_init: true)

        def self.call(customer_id:, email:)
          user = lookup(customer_id, email)
          hit  = user.present? && user.member? && user.mfa_configured?

          if hit
            token = Member::Mfa::ResetToken.generate(user)
            Member::MfaMailer.with(user: user, token: token).reset_link.deliver_later
          end

          Rails.logger.info(
            event:       "member_mfa_reset_requested",
            customer_id: customer_id,
            hit:         hit
          )

          Result.new(success?: true)
        end

        def self.lookup(customer_id, email)
          return nil if email.blank?

          ::Authentication::User
            .where(customer_id: customer_id)
            .find_by("LOWER(email) = ?", email.to_s.downcase.strip)
        end
        private_class_method :lookup
      end
    end
  end
end
