# frozen_string_literal: true

module FlowchartDefinitions
  module Assistant
    # Second chat completion of an assistant turn: one flowchart, with a
    # bounded LLM repair round-trip (AiAssistant::Assistant::DocumentRepair)
    # when validation fails. Confirmation is pinned to the first persistable
    # document so a repair cannot self-approve an update.
    class Processor
      MAX_REPAIR = 2
      LOG_TAG = "[flowchart_definitions.assistant]"
      Message = Struct.new(:body, :status, :created, :updated, :proposal, :intent, keyword_init: true)

      # `screen` is an optional callable taking the normalized document and
      # returning extra error strings; they go through the same repair loop as
      # validation errors, so a caller can refuse content the validators allow.
      # `replaceable` names the one flowchart the caller already approved
      # rewriting; repairs still run, and any other name match still waits
      # for confirmation.
      def self.call(conversation:, customer:, chat:, text: nil, confirmed: false,
                    write_guard: nil, screen: nil, replaceable: nil)
        new(
          conversation: conversation,
          customer: customer,
          chat: chat,
          text: text,
          confirmed: confirmed,
          write_guard: write_guard,
          screen: screen,
          replaceable: replaceable
        ).call
      end

      def initialize(conversation:, customer:, chat:, text:, confirmed:, write_guard:, screen:, replaceable: nil)
        @conversation = conversation
        @customer = customer
        @chat = chat
        @text = text
        @confirmed = confirmed
        @write_guard = write_guard
        @screen = screen
        @replaceable = replaceable
      end

      def call
        text = @text.presence || complete(prompt_messages)
        return vendor_failure if text.nil?

        extraction = Extraction.parse(text)
        return invalid_extraction unless extraction.valid?
        unless extraction.persistable?
          return Message.new(body: extraction.reply, status: "complete", intent: extraction.intent)
        end

        persist_with_repair(extraction, confirmed: @confirmed)
      end

      private

      def persist_with_repair(extraction, confirmed:)
        (MAX_REPAIR + 1).times do |attempt|
          decision = UpdatePolicy.call(
            flowchart: extraction.flowchart,
            customer: @customer,
            confirmed: confirmed,
            replaceable: @replaceable
          )
          return awaiting_confirmation(extraction, decision) unless decision.permitted?

          normalized = Normalizer.call(extraction.flowchart)
          errors = SchemaValidator.call(extraction).errors +
                   GraphValidator.call(normalized: normalized, customer: @customer).errors +
                   Array(@screen&.call(normalized))
          if errors.empty?
            result = guarded_persist(normalized)
            return Message.new(
              body: success_body(extraction.reply, result),
              status: "complete",
              created: result.created,
              updated: result.updated
            ) if result.ok?

            errors = result.errors
          end

          return give_up(extraction, errors) if confirmed || attempt >= MAX_REPAIR

          repaired = repaired_extraction(extraction, errors)
          return give_up(extraction, errors) if repaired.nil?

          extraction = repaired
        end
      end

      def guarded_persist(normalized)
        AiAssistant::Assistant::GenerationWriteGuard.wrap(@write_guard) do
          Persist.call(normalized: normalized, customer: @customer)
        end
      end

      def repaired_extraction(extraction, errors)
        repair.call(document: extraction.as_json, errors: errors)
      end

      def repair
        @repair ||= AiAssistant::Assistant::DocumentRepair.new(
          conversation: @conversation,
          chat: @chat,
          mode: :flowchart,
          instructions: "flowchart_repair",
          parser: Extraction
        )
      end

      def complete(messages)
        result = @chat.call(messages)
        text = result.is_a?(Hash) ? result[:text].to_s.strip : ""
        outcome = result.is_a?(Hash) ? result[:outcome] : nil
        return text if outcome == :success && text.present?

        nil
      end

      def prompt_messages
        AiAssistant::Assistant::PromptBuilder.call(
          conversation: @conversation,
          mode: :flowchart
        )
      end

      def success_body(reply, result)
        prose = reply unless @confirmed && result.updated.present?
        notes = []
        notes << I18n.t("ai_assistant.assistant.apply_flowchart_created", names: result.created) if result.created.present?
        notes << I18n.t("ai_assistant.assistant.apply_flowchart_updated", names: result.updated) if result.updated.present?
        AiAssistant::Assistant::Markdown.compose(prose, notes)
      end

      def awaiting_confirmation(extraction, decision)
        record = Flowchart.where(
          customer_id: @customer.id,
          name: decision.existing_names
        ).first
        Message.new(
          # Its own key, not the entity one: the entity wording points at the
          # change panel below the reply, and ProposedChangesComponent only
          # renders an entity proposal. A flowchart update is still confirmed
          # by replying with a yes.
          body: [extraction.reply, I18n.t("ai_assistant.assistant.flowchart_needs_confirmation")].join(" ").strip,
          status: "complete",
          proposal: AiAssistant::Assistant::PendingConfirmation.build(
            kind: "flowchart",
            document: extraction.as_json,
            customer: @customer,
            record: record
          )
        )
      end

      def give_up(extraction, errors)
        Message.new(
          body: [extraction.reply, Array(errors).map(&:to_s).reject(&:blank?).join(" ")].join(" ").strip,
          status: "complete"
        )
      end

      def invalid_extraction
        Message.new(body: I18n.t("ai_assistant.assistant.extraction_invalid"), status: "failed")
      end

      def vendor_failure
        Message.new(body: I18n.t("ai_assistant.assistant.flowchart_reply_failed"), status: "failed")
      end
    end
  end
end
