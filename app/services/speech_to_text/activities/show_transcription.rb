# frozen_string_literal: true

module SpeechToText
  module Activities
    # Read-path for a desktop STT poll. Scoped to the URL tenant and the
    # token owner — never returns another user's clip.
    class ShowTranscription
      Result = Struct.new(:success?, :clip, :http_status, :errors, keyword_init: true)

      def self.call(customer:, user:, clip_id:)
        new(customer: customer, user: user, clip_id: clip_id).call
      end

      def initialize(customer:, user:, clip_id:)
        @customer = customer
        @user = user
        @clip_id = clip_id
      end

      def call
        clip = SpeechToText::Clip.find_by(id: clip_id, customer_id: customer.id, user_id: user.id)
        return fail_result unless clip

        Result.new(success?: true, clip: clip, http_status: 200, errors: [])
      end

      private

      attr_reader :customer, :user, :clip_id

      def fail_result
        Result.new(success?: false, clip: nil, http_status: 404, errors: [])
      end
    end
  end
end
