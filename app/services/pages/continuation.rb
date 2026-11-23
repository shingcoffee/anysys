# frozen_string_literal: true

module Pages
  # Signs `{ action_key, prefill }` so a public registration can resume the
  # same action as a member. The token is not tenant-bound: Claim.complete!
  # builds the path for the signed-in user's own customer.
  class Continuation
    PURPOSE = "page_continuation"
    EXPIRES_IN = 3.days
    MAX_TOKEN_BYTES = 8.kilobytes

    def self.sign(action_key:, prefill: {})
      verifier.generate(
        { "action_key" => action_key.to_s, "prefill" => ActionLink.sanitized_prefill(prefill) },
        purpose: PURPOSE,
        expires_in: EXPIRES_IN
      )
    end

    # Returns `{ action_key:, prefill: }` or nil. Never raises.
    def self.verify(token)
      return unless token.is_a?(String) && token.bytesize <= MAX_TOKEN_BYTES

      payload = verifier.verified(token, purpose: PURPOSE)
      return unless payload.is_a?(Hash)

      data = payload.stringify_keys
      action_key = data["action_key"].to_s
      return unless action_key.match?(PageVisibility::ACTION_KEY)

      prefill = data["prefill"]
      prefill = {} unless prefill.is_a?(Hash)

      { action_key: action_key, prefill: ActionLink.sanitized_prefill(prefill) }
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
