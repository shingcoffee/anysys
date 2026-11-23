# frozen_string_literal: true

module Authentication
  # Single-use consumption of an emailed sign-in token.
  #
  # Eligibility is screened BEFORE the token is claimed, so a locked,
  # deactivated, unconfirmed, or auth-disabled account does not burn its link
  # on a request that could never have signed in. SignInFlow re-checks the
  # same conditions; this is the pre-flight, not the authorization decision.
  class ConsumeSignInLink
    Result = Struct.new(:success?, :user, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(token:)
      @token = token.to_s
    end

    def call
      return failure if @token.blank?

      hashed = Devise.token_generator.digest(User, :sign_in_token, @token)
      user = User.find_by(sign_in_token: hashed)
      return failure unless user

      user.with_lock do
        next failure unless user.sign_in_token == hashed && eligible?(user)
        next failure unless claim(user.id, hashed)

        user.reload
        Result.new(success?: true, user: user)
      end
    end

    private

    # Atomic single-use claim. Two concurrent requests on the same link both
    # pass the read above; only the UPDATE that still matches a populated
    # sign_in_token affects a row, so exactly one caller can win and a replay
    # sees zero rows. update_all skips callbacks and updated_at deliberately
    # (see IssueSignInLink) — clearing the token is not a credential change.
    def claim(user_id, hashed)
      User.where(id: user_id, sign_in_token: hashed)
          .update_all(sign_in_token: nil, sign_in_token_sent_at: nil)
          .positive?
    end

    def eligible?(user)
      user.confirmed? &&
        user.active? &&
        !user.access_locked? &&
        !expired?(user) &&
        FeatureModules::Module.enabled?(key: "authentication", customer_id: user.customer_id)
    end

    def expired?(user)
      user.sign_in_token_sent_at.blank? ||
        user.sign_in_token_sent_at < IssueSignInLink::TOKEN_TTL.ago
    end

    def failure
      Result.new(success?: false, user: nil)
    end
  end
end
