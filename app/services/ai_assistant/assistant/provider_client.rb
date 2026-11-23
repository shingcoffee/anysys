# frozen_string_literal: true

module AiAssistant
  module Assistant
    # The one seam between the turn pipeline and a vendor.
    #
    # Besides normalising transport failures it owns the per-turn call budget.
    # A turn is not one completion: the tool loop, the flowchart pass and
    # each repair round-trip all come through here, and
    # before this counter existed the worst case was unbounded — every one of
    # those is a billed call. AiAssistant::Limits caps how many turns a user
    # may take; this caps what a single turn may spend.
    class ProviderClient
      LOG_TAG = "[ai_assistant.provider_client]"
      PROVIDER_ERRORS = [
        RubyLLM::Error,
        Faraday::Error,
        OutboundHttp::TransportError
      ].freeze

      attr_reader :tool_session, :calls

      def initialize(settings:, conversation:, tool_session: nil, budget: AiAssistant::Limits::MAX_VENDOR_CALLS,
                     write_guard: nil)
        @settings = settings
        @conversation = conversation
        @budget = budget
        @calls = 0
        @write_guard = write_guard
        @tool_session = tool_session || AiAssistant::Assistant::Tools::Session.new(
          customer: conversation.customer,
          viewer: conversation.user
        )
      end

      # @param on_chunk [#call, nil] live token sink. Ignored unless the vendor
      #   declares support, so a caller may always pass one.
      def chat(messages, tools: nil, on_chunk: nil)
        check_generation!
        return budget_exceeded if exhausted?

        options = { messages: messages, tools: tools, on_chunk: streaming_sink(on_chunk) }
        if @settings.provider_class.supports_native_tools?
          options[:before_request] = method(:reserve_request!)
          options[:before_tool_call] = method(:check_generation!)
        else
          reserve_request!
        end
        provider.chat(**options)
      rescue Llm::CallBudgetExceeded
        budget_exceeded
      rescue *PROVIDER_ERRORS => e
        Rails.logger.error(
          "#{LOG_TAG} provider call failed conversation=#{@conversation.id}: #{e.class}: #{e.message}"
        )
        { outcome: :unreachable, text: nil, raw: { "error" => e.class.name } }
      end

      def streaming?
        @settings.provider_class.supports_streaming?
      end

      # Each vendor declares its own tool support (Providers::Base
      # #supports_native_tools?), so a new generation vendor stays a
      # single-file addition.
      def native_tools
        return [] unless @settings.provider_class.supports_native_tools?

        tool_session.native_tools
      end

      private

      def check_generation!
        @write_guard&.check!
      end

      def reserve_request!
        check_generation!
        raise Llm::CallBudgetExceeded, "vendor_call_budget" if exhausted?

        @calls += 1
      end

      def streaming_sink(on_chunk)
        streaming? ? on_chunk : nil
      end

      def exhausted?
        @calls >= @budget
      end

      def budget_exceeded
        Rails.logger.warn(
          "#{LOG_TAG} per-turn call budget #{@budget} exhausted conversation=#{@conversation.id}"
        )
        { outcome: :budget_exceeded, text: nil, raw: { "error" => "vendor_call_budget" } }
      end

      def provider
        @provider ||= @settings.provider_class.new(settings: @settings)
      end
    end
  end
end
