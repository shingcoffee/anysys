# frozen_string_literal: true

module Payments
  module Admin
    # Renders the Test Connection result region for the gateway config form.
    # state ∈ :idle | :loading | :success | :error
    #
    # Used both as a static initial render (idle/hidden) and as a Turbo stream
    # partial replacement when the gateway-config Stimulus controller gets
    # the JSON result back from the test_connection endpoint.
    class TestConnectionResultComponent < ApplicationComponent
      attr_reader :state, :message, :verified_at

      def initialize(state: :idle, message: nil, verified_at: nil)
        @state       = state.to_sym
        @message     = message
        @verified_at = verified_at
      end

      def idle?    = state == :idle
      def loading? = state == :loading
      def success? = state == :success
      def error?   = state == :error

      def container_classes
        base = "rounded-lg px-4 py-3 flex items-start gap-2"
        case state
        when :loading then "#{base} bg-canvas-elevated"
        when :success then "#{base} bg-success-subtle border border-success/30"
        when :error   then "#{base} bg-danger-subtle border border-danger/30"
        else               "#{base}"
        end
      end
    end
  end
end
