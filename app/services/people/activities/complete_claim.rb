# frozen_string_literal: true

module People
  module Activities
    class CompleteClaim < Trailblazer::Activity::Railway
      step :find_claim
      step :check_expiry_and_tenant
      step :link_entry
      step :consume
      step :build_path

      def self.call(user:)
        Customer.find(user.customer_id).with_lock(requires_new: true) do
          _signal, (ctx, _) = super([{ user: user }, {}])
          ctx[:path]
        end
      end

      def find_claim(ctx, user:, **)
        claim = PendingClaim.find_by(user_id: user.id)
        return false unless claim

        ctx[:claim] = claim
        true
      end

      def check_expiry_and_tenant(_ctx, claim:, user:, **)
        claim.expires_at > Time.current && claim.customer_id == user.customer_id
      end

      def link_entry(_ctx, claim:, user:, **)
        entry = claim.entity_entry
        return true unless entry
        return true if entry.linked?
        return true if entry.customer_id != user.customer_id

        People::Link.link!(entry: entry, user_id: user.id, actor: user, event: "person.claimed")
        true
      end

      def consume(_ctx, claim:, **)
        claim.destroy!
        true
      end

      def build_path(ctx, claim:, user:, **)
        ctx[:path] = continuation_path(user, claim.continuation)
        true
      end

      private

      def continuation_path(user, payload)
        return unless payload.is_a?(Hash)

        data = payload.stringify_keys
        action_key = data["action_key"].to_s
        return unless action_key.match?(PageVisibility::ACTION_KEY)

        prefill = data["prefill"]
        prefill = {} unless prefill.is_a?(Hash)
        Pages::ActionLink.path(customer_id: user.customer_id, action_key: action_key, prefill: prefill)
      end
    end
  end
end
