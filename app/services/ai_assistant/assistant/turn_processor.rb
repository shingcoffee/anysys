# frozen_string_literal: true

module AiAssistant
  module Assistant
    class TurnProcessor
      Result = Struct.new(
        :body,
        :status,
        :entity_result,
        :flowchart_result,
        :website_result,
        :effects,
        :pending_confirmation,
        :confirmation_applied,
        :questions,
        :assumptions,
        keyword_init: true
      )

      EntityTurn = Struct.new(
        :body,
        :status,
        :intent,
        :applied,
        :created,
        :updated,
        :bridges,
        :proposal,
        :questions,
        :assumptions,
        :flowchart_requested,
        keyword_init: true
      )

      def self.call(text: nil, proposal: nil, conversation:, customer:, chat:, tool_session: nil,
                    write_guard: nil, progress: nil)
        new(
          text: text,
          proposal: proposal,
          conversation: conversation,
          customer: customer,
          chat: chat,
          tool_session: tool_session,
          write_guard: write_guard,
          progress: progress
        ).call
      end

      def initialize(text:, proposal:, conversation:, customer:, chat:, tool_session:, write_guard:,
                     progress: nil)
        @text = text
        @proposal = proposal
        @conversation = conversation
        @customer = customer
        @chat = chat
        @write_guard = write_guard
        @progress = progress || AiAssistant::Assistant::Progress.null
        @tool_session = tool_session || AiAssistant::Assistant::Tools::Session.new(
          customer: customer,
          write_guard: write_guard,
          viewer: conversation.user,
          conversation: conversation
        )
      end

      def call
        return apply_proposal if @proposal

        loop_result = AiAssistant::Assistant::Loop.call(
          text: @text,
          conversation: @conversation,
          customer: @customer,
          chat: @chat,
          tool_session: @tool_session
        )
        unless loop_result.outcome == :success
          @progress.fail!
          return result(
            I18n.t("ai_assistant.assistant.reply_failed"),
            "failed",
            entity_result: nil
          )
        end
        return run_website(loop_result.text) if Websites::Assistant::Extraction.website_document?(loop_result.text)

        entity_result = synthesize_entity_turn(loop_result.text)
        unless flowchart_follow_on?(entity_result)
          return result(
            entity_result.body,
            entity_result.status,
            entity_result: entity_result,
            pending_confirmation: entity_result.proposal
          )
        end

        flowchart_result = run_flowchart
        result(
          joined_body(entity_result, flowchart_result),
          joined_status(entity_result, flowchart_result),
          entity_result: entity_result,
          flowchart_result: flowchart_result,
          pending_confirmation: flowchart_result.proposal
        )
      end

      private

      def synthesize_entity_turn(text)
        envelope = ReplyEnvelope.parse(text)
        return entity_turn(t("extraction_invalid"), status: "failed") unless envelope.valid?

        created, updated, bridges = collect_write_names
        applied = entity_write_succeeded?
        proposal = @tool_session.pending_proposal
        entity_turn(
          entity_body(envelope.reply, applied: applied, created: created, updated: updated, bridges: bridges, proposal: proposal),
          intent: envelope.intent,
          applied: applied,
          created: created,
          updated: updated,
          bridges: bridges,
          proposal: proposal,
          questions: envelope.questions,
          assumptions: envelope.assumptions,
          flowchart_requested: envelope.flowchart_requested
        )
      end

      def entity_write_succeeded?
        @tool_session.operation_outcomes.any? do |outcome|
          outcome.status == "succeeded" && entity_operation?(outcome.operation) && outcome.operation != "get_entity"
        end
      end

      def entity_operation?(key)
        Tools::Session::ENTITY_OPERATIONS.include?(key.to_s)
      end

      # Only entity operations report entity names; another operation's
      # created/updated lists name other kinds of records.
      def collect_write_names
        created = []
        updated = []
        bridges = []
        @tool_session.operation_outcomes.each do |outcome|
          data = outcome.data
          next unless outcome.status == "succeeded" && entity_operation?(outcome.operation) && data.is_a?(Hash)

          created.concat(named_rows(data["created"]))
          updated.concat(named_rows(data["updated"]))
          bridges.concat(Array(data["bridges"]))
        end
        # A repeated identical call is replayed from the audit row, so the same
        # write can appear twice in one turn.
        [created.uniq, updated.uniq, bridges.uniq]
      end

      def named_rows(rows)
        Array(rows).filter_map { |row| row.is_a?(Hash) ? row["name"] : row }
      end

      def entity_body(reply, applied:, created:, updated:, bridges:, proposal:)
        notes = []
        if applied
          notes << t("apply_created", names: created.join(", ")) if created.any?
          notes << t("apply_updated", names: updated.join(", ")) if updated.any?
          notes << t("apply_bridges", names: bridges.join(", ")) if bridges.any?
        end
        notes << t("update_needs_confirmation") if proposal
        Markdown.compose(reply, notes)
      end

      # A website document never carries entities, so it skips the entity and
      # flowchart passes entirely rather than being rejected by their parsers.
      def run_website(text)
        @progress.start(:website)
        website_result = Websites::Assistant::Processor.call(
          text: text,
          customer: @customer,
          conversation: @conversation,
          chat: @chat,
          write_guard: @write_guard
        )
        result(
          website_result.body,
          website_result.status,
          entity_result: nil,
          website_result: website_result
        )
      end

      # The flowchart pass designs a flowchart from the whole conversation, so
      # a reply that wrote nothing hands over only when the entity pass asked
      # for it; a greeting or a question must never start a design. A started
      # sub-system build writes the processing the conversation asks for, so
      # a design pass would leave a second, unbound copy of it.
      def flowchart_follow_on?(entity_result)
        return false unless flowchart_visible?
        return false if subsystem_build_started?

        entity_result.status == "complete" &&
          entity_result.proposal.blank? &&
          (entity_result.applied || flowchart_requested?(entity_result))
      end

      def flowchart_requested?(entity_result)
        entity_result.intent == ReplyEnvelope::Intent::CHAT && entity_result.flowchart_requested
      end

      def subsystem_build_started?
        @tool_session.operation_outcomes.any? do |outcome|
          outcome.operation == Operations::StartSubsystemBuild.key && outcome.status == "succeeded"
        end
      end

      def run_flowchart
        @progress.start(:flowchart)
        FlowchartDefinitions::Assistant::Processor.call(
          conversation: @conversation,
          customer: @customer,
          chat: @chat,
          write_guard: @write_guard
        )
      end

      def joined_body(entity_result, flowchart_result)
        entity_body = entity_result.body.to_s.strip
        return entity_body if hide_flowchart_failure?(entity_result, flowchart_result)
        return entity_body if flowchart_small_talk?(entity_body, flowchart_result)

        Markdown.paragraphs(entity_body, flowchart_result.body)
      end

      # The entity pass has already answered a conversational turn; a flowchart
      # pass that changed nothing only restates that answer in its own words.
      def flowchart_small_talk?(entity_body, flowchart_result)
        entity_body.present? &&
          flowchart_result.intent == FlowchartDefinitions::Assistant::Extraction::Intent::CHAT
      end

      def joined_status(entity_result, flowchart_result)
        return "failed" if entity_result.status == "failed"
        return "complete" if entity_result.applied
        return "complete" if hide_flowchart_failure?(entity_result, flowchart_result)

        flowchart_result.status
      end

      def hide_flowchart_failure?(entity_result, flowchart_result)
        flowchart_result.status == "failed" &&
          !entity_result.applied &&
          entity_result.intent == ReplyEnvelope::Intent::CHAT &&
          entity_result.body.to_s.strip.present?
      end

      def apply_proposal
        case @proposal.fetch("kind")
        when "operation"
          apply_operation_proposal
        when "flowchart"
          apply_flowchart_proposal
        else
          raise ArgumentError, "unsupported proposal kind"
        end
      end

      def apply_operation_proposal
        @progress.start(:entity)
        invocation = OperationInvocation.find_by(
          id: @proposal["invocation_id"],
          customer_id: @customer.id,
          conversation_id: @conversation.id
        )
        return failed_confirmation unless invocation

        outcome = Operations::Activities::Confirm.call(
          invocation: invocation,
          context: Operations::Context.new(
            customer: @customer,
            actor: @conversation.user,
            channel: "assistant",
            conversation: @conversation
          )
        )
        map_confirmation(outcome)
      end

      # Entity results feed page generation and the entity change list. Any
      # other operation is summarised generically; the plan the admin
      # approved already said what it changes.
      def map_confirmation(outcome)
        entity = entity_operation?(outcome.operation)
        case outcome.status
        when "succeeded"
          unless entity
            turn = entity_turn(t("operation_applied"))
            return result(turn.body, "complete", entity_result: turn, confirmation_applied: true)
          end

          updated = named_rows(outcome.data&.fetch("updated", nil))
          bridges = Array(outcome.data&.fetch("bridges", nil))
          notes = []
          notes << t("apply_updated", names: updated.join(", ")) if updated.any?
          notes << t("apply_bridges", names: bridges.join(", ")) if bridges.any?
          turn = entity_turn(Markdown.compose(nil, notes), applied: true, updated: updated, bridges: bridges)
          result(turn.body, "complete", entity_result: turn, confirmation_applied: true)
        when "conflict"
          turn = entity_turn(t(entity ? "proposal_stale" : "operation_stale"))
          result(turn.body, "complete", entity_result: turn)
        else
          failed_confirmation
        end
      end

      def failed_confirmation
        turn = entity_turn(t("reply_failed"), status: "failed")
        result(turn.body, "failed", entity_result: turn)
      end

      def apply_flowchart_proposal
        unless flowchart_visible?
          return result(
            I18n.t("ai_assistant.assistant.reply_failed"),
            "failed",
            entity_result: nil
          )
        end

        @progress.start(:flowchart)
        flowchart_result = FlowchartDefinitions::Assistant::Processor.call(
          conversation: @conversation,
          customer: @customer,
          chat: @chat,
          text: @proposal.fetch("document").to_json,
          confirmed: true,
          write_guard: @write_guard
        )
        result(
          flowchart_result.body,
          flowchart_result.status,
          entity_result: nil,
          flowchart_result: flowchart_result,
          confirmation_applied: flowchart_result.created.present? ||
            flowchart_result.updated.present?
        )
      end

      def flowchart_visible?
        FlowchartVisibility.allowed?(@conversation.user)
      end

      def entity_turn(body, status: "complete", intent: nil, applied: false, created: [], updated: [],
                      bridges: [], proposal: nil, questions: nil, assumptions: nil, flowchart_requested: false)
        EntityTurn.new(
          body: body,
          status: status,
          intent: intent,
          applied: applied,
          created: Array(created),
          updated: Array(updated),
          bridges: Array(bridges),
          proposal: proposal,
          questions: questions,
          assumptions: assumptions,
          flowchart_requested: flowchart_requested
        )
      end

      def t(key, **options)
        I18n.t("ai_assistant.assistant.#{key}", **options)
      end

      def result(body, status, entity_result:, flowchart_result: nil, website_result: nil,
                 pending_confirmation: nil, confirmation_applied: false)
        Result.new(
          body: body,
          status: status,
          entity_result: entity_result,
          flowchart_result: flowchart_result,
          website_result: website_result,
          effects: @tool_session.effects,
          pending_confirmation: pending_confirmation,
          confirmation_applied: confirmation_applied,
          questions: entity_result&.questions,
          assumptions: entity_result&.assumptions
        )
      end
    end
  end
end
