# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Rate-limits the live reply preview.
    #
    # A vendor emits tokens far faster than a browser needs repaints, and every
    # broadcast is a Markdown render plus an ActionCable frame. This coalesces
    # them: a frame goes out when enough new prose has accumulated, or when
    # enough time has passed for a slow trickle to still feel alive.
    class DeltaPump
      MIN_INTERVAL = 0.12
      MIN_GROWTH = 24

      def initialize(conversation:, publisher: AiAssistant::Stream, clock: nil, cancelled: nil)
        @conversation = conversation
        @publisher = publisher
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @cancelled = cancelled
        @cancelled_latched = false
        @raw = +""
        @published = ""
        @published_at = nil
        @scanned_at = nil
        @visible = ""
      end

      attr_reader :raw

      # One turn can make several vendor calls, each returning its own
      # document. Accumulating across them would splice two unrelated JSON
      # bodies together, so the buffer restarts per call. What was already
      # published stays: a call that yields no prose leaves the previous
      # preview on screen rather than blanking it.
      def begin_call
        @raw = +""
        @scanned_at = nil
        @visible = ""
      end

      def call(chunk)
        push(chunk)
      end

      def push(chunk)
        text = chunk.to_s
        return if text.empty?

        @raw << text
        publish if due?
      end

      # Forces out whatever the last push withheld, so the preview always ends
      # on the complete text rather than one coalescing window short of it.
      def flush
        publish
      end

      private

      # Each scan walks the whole buffer, and both due? and publish ask for it,
      # so an unmemoised call would make the preview quadratic in reply length.
      #
      # scrub is the backstop: a lone surrogate or other malformed escape must
      # never reach Markdown, which raises on invalid UTF-8 and would take the
      # turn down with it.
      def visible
        return @visible if @scanned_at == @raw.length

        @scanned_at = @raw.length
        @visible = AiAssistant::Assistant::StreamingText.visible(@raw).scrub
      end

      def due?
        return false if @conversation.nil?

        candidate = visible
        return false if candidate == @published

        elapsed = @published_at.nil? || (@clock.call - @published_at) >= MIN_INTERVAL
        elapsed || (candidate.length - @published.length) >= MIN_GROWTH
      end

      # Stop leaves the vendor request in flight, so chunks keep arriving after
      # the generation is cancelled. Freezing the preview here is what makes
      # Stop look like it worked. Cancellation is terminal, so the answer is
      # latched rather than re-read for every remaining frame.
      def cancelled?
        @cancelled_latched ||= @cancelled.present? && @cancelled.call == true
      end

      def publish
        return if @conversation.nil?
        return if cancelled?

        candidate = visible
        return if candidate == @published || candidate.empty?

        @published = candidate
        @published_at = @clock.call
        @publisher.broadcast_delta(@conversation, candidate)
      end
    end
  end
end
