# frozen_string_literal: true

module AiAssistant
  # Every ceiling the assistant enforces, in one place.
  #
  # Each turn costs a paid vendor call (often several, once the tool loop and
  # the repair round-trips are counted) and grows the prompt, so the assistant
  # is throttled on three axes:
  #
  #   * BURST   — stops a held Enter key or a double-click storm.
  #   * SUSTAINED — caps what one admin can spend in an hour.
  #   * TURNS   — caps how long one thread runs before it is reset, which keeps
  #               the replayed history bounded and the context coherent.
  #
  # Adjust a number here and the request path, the composer and the UI copy all
  # follow; nothing else hard-codes a limit.
  module Limits
    # One throttled window. `message_key` is resolved under
    # `ai_assistant.errors` when the window is breached.
    Window = Struct.new(:name, :limit, :period, :message_key, keyword_init: true)

    BURST = Window.new(name: "burst", limit: 5, period: 15.seconds, message_key: "rate_limited_burst").freeze
    SUSTAINED = Window.new(name: "hourly", limit: 30, period: 1.hour, message_key: "rate_limited").freeze

    WINDOWS = [BURST, SUSTAINED].freeze

    # Maximum user turns in one conversation before it must be reset.
    MAX_TURNS = 40

    # Vendor calls one turn may spend across the tool loop, the entity and
    # flowchart passes and their repair round-trips. Without it the worst case
    # multiplies out to dozens of billed calls behind a single user message;
    # AiAssistant::Assistant::ProviderClient enforces it.
    MAX_VENDOR_CALLS = 12

    # Show the remaining-turns hint once the thread gets this close to the cap.
    TURNS_WARNING_THRESHOLD = 5

    module_function

    def turns_remaining(used)
      [MAX_TURNS - used.to_i, 0].max
    end

    def turns_exhausted?(used)
      turns_remaining(used).zero?
    end

    def turns_warning?(used)
      remaining = turns_remaining(used)
      remaining.positive? && remaining <= TURNS_WARNING_THRESHOLD
    end
  end
end
