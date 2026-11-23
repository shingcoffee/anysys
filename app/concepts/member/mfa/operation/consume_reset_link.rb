# frozen_string_literal: true

module Member
  module Mfa
    module Operation
      class ConsumeResetLink
        Result = Struct.new(:success?, :user, :reason, keyword_init: true)

        def self.call(token:, request: nil, actor: nil)
          verification = Member::Mfa::ResetToken.consume(token) do |user|
            Authentication::MutationAudit.mfa(user: user, request: request,
                                              actor: actor, source: "recovery") { user.disable_mfa! }
          end
          return failure(verification.reason) unless verification.success?

          user = verification.user

          Result.new(success?: true, user: user, reason: nil)
        end

        def self.failure(reason)
          Result.new(success?: false, user: nil, reason: reason)
        end
        private_class_method :failure
      end
    end
  end
end
