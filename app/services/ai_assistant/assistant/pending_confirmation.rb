# frozen_string_literal: true

module AiAssistant
  module Assistant
    class PendingConfirmation
      SUPPORTED_KINDS = %w[operation flowchart].freeze
      SETTLED_KEYS = %w[applied_proposal declined_proposal superseded_proposal].freeze

      class << self
        # `plan` is the reviewable diff shown alongside the proposal. It is
        # display only: the apply path replays the parked invocation (or the
        # flowchart document) through the writer, so nothing here can widen a write.
        def build(kind:, document:, customer:, record: nil, records: nil, plan: nil)
          targets = Array(records || record).compact.map do |target|
            {
              "id" => target.id,
              "name" => target.name,
              "version_id" => current_version_id(target)
            }
          end
          proposal = {
            "kind" => kind.to_s,
            "customer_id" => customer.id,
            "document" => document.deep_stringify_keys,
            "targets" => targets
          }
          proposal["plan"] = Array(plan) if plan.present?
          proposal
        end

        # Retires every proposal still pending in a thread, so the one being
        # parked right now is the only live one. Called by ReplyWriter from
        # inside the transaction that writes the new message.
        #
        # Apply (pinned) and Discard name a specific message; a typed yes/no
        # only acts when that live proposal is the latest complete assistant
        # turn. A proposal left pending after the admin moved on would still
        # be a live Apply target, so parking a new one must retire the old.
        #
        # Moved, not deleted: the transcript keeps showing what was proposed,
        # and `superseded_proposal` is what tells the panel it is a record of a
        # past offer rather than a live one.
        def retire_open!(conversation)
          # The same conversation row #consume locks. Fetched rather than
          # reloaded through the caller's record, which may be holding changes
          # of its own.
          conversation.class.lock.find_by(id: conversation.id)

          conversation.messages.with_pending_proposal.lock.each { |message| retire_message!(message) }
        end

        # Caller holds the conversation lock. True when a live
        # `pending_confirmation` on an assistant message was moved to
        # `declined_proposal`.
        def decline!(message, actor:)
          return false unless message&.assistant?

          metadata = message.metadata_json.deep_dup
          declined = metadata.delete("pending_confirmation")
          return false if declined.blank?

          decline_operation!(declined, actor: actor, conversation: message.conversation)
          metadata["declined_proposal"] = declined
          message.update!(metadata: metadata)
          true
        end

        def consume(conversation:, user_message:, generation:)
          decision = decision_for(user_message.body)
          return unless decision

          changed_message = nil
          result = conversation.with_lock do
            generation.reload
            return unless current_generation?(
              conversation: conversation,
              user_message: user_message,
              generation: generation
            )

            target = target_message(conversation, user_message, decision)
            next unless target
            next not_pending_result if target == :not_pending

            if decision == :decline
              if decline!(target, actor: conversation.user)
                changed_message = target
                declined_result
              else
                not_pending_result
              end
            else
              proposal = proposal_from(target)
              operation = -> { valid_proposal?(proposal, conversation) ? yield(proposal) : nil }
              outcome = if proposal.is_a?(Hash) && proposal["kind"] == "operation"
                          conversation.customer.with_lock(&operation)
                        else
                          operation.call
                        end
              if confirmation_applied?(outcome)
                consume_proposal!(target, generation)
                changed_message = target
              elsif dead_operation_proposal?(proposal)
                retire_message!(target)
                changed_message = target
              end
              outcome
            end
          end

          # The panel that offered Apply is sitting on its pending state; the
          # row behind it has just changed and nothing else re-renders that
          # bubble. Broadcast after the lock, so what goes out is committed.
          AiAssistant::Stream.broadcast_message_replace(changed_message) if changed_message
          result
        end

        private

        def decision_for(body)
          return :approve if explicit_confirmation?(body)
          return :decline if explicit_rejection?(body)

          nil
        end

        def target_message(conversation, user_message, decision)
          pin_id = user_message.metadata_json["confirms_message_id"]
          if decision == :approve && pin_id.present?
            return pinned_target(conversation, user_message, pin_id)
          end

          typed_target(conversation, user_message)
        end

        def pinned_target(conversation, user_message, pin_id)
          message = locked_complete_assistant_messages(conversation, user_message).find_by(id: pin_id)
          pending_proposal?(message) ? message : :not_pending
        end

        def typed_target(conversation, user_message)
          message = locked_complete_assistant_messages(conversation, user_message).order(id: :desc).first
          return if message.nil?
          return if pending_proposal?(message) && questions?(message)
          return message if pending_proposal?(message)
          return :not_pending if settled_proposal?(message)

          nil
        end

        def locked_complete_assistant_messages(conversation, user_message)
          conversation.messages
                      .where(role: "assistant", status: "complete")
                      .where("id < ?", user_message.id)
                      .lock
        end

        def pending_proposal?(message)
          proposal_from(message).present?
        end

        def questions?(message)
          message.metadata_json["questions"].present?
        end

        def settled_proposal?(message)
          metadata = message.metadata_json
          SETTLED_KEYS.any? { |key| metadata[key].present? }
        end

        def not_pending_result
          confirmation_notice(I18n.t("ai_assistant.assistant.proposal_not_pending"))
        end

        def declined_result
          confirmation_notice(I18n.t("ai_assistant.assistant.plan.declined"))
        end

        def confirmation_notice(body)
          TurnProcessor::Result.new(body: body, status: "complete", effects: [])
        end

        def retire_message!(message)
          metadata = message.metadata_json.deep_dup
          retired = metadata.delete("pending_confirmation")
          return if retired.blank?

          supersede_operation!(retired)
          metadata["superseded_proposal"] = retired
          message.update!(metadata: metadata)
        end

        # A parked invocation that Confirm already settled (conflict, invalid,
        # failed) can never apply, so its panel must stop offering Apply.
        def dead_operation_proposal?(proposal)
          return false unless proposal.is_a?(Hash) && proposal["kind"] == "operation"

          invocation = OperationInvocation.find_by(id: proposal["invocation_id"], customer_id: proposal["customer_id"])
          invocation.present? && !invocation.awaiting_confirmation?
        end

        def supersede_operation!(proposal)
          return unless proposal.is_a?(Hash) && proposal["kind"] == "operation"
          return if proposal["invocation_id"].blank?

          invocation = OperationInvocation.find_by(
            id: proposal["invocation_id"],
            customer_id: proposal["customer_id"]
          )
          return unless invocation&.awaiting_confirmation?

          Operations::Activities::Confirm.supersede!(invocation)
        end

        def decline_operation!(proposal, actor:, conversation:)
          return unless proposal.is_a?(Hash) && proposal["kind"].to_s == "operation"
          return if proposal["invocation_id"].blank?

          invocation = OperationInvocation.find_by(
            id: proposal["invocation_id"],
            customer_id: conversation.customer_id,
            conversation_id: conversation.id
          )
          return unless invocation&.awaiting_confirmation?

          Operations::Activities::Confirm.decline!(invocation, actor: actor)
        end

        def current_generation?(conversation:, user_message:, generation:)
          generation.status == "running" &&
            generation.conversation_id == conversation.id &&
            generation.customer_id == conversation.customer_id &&
            generation.user_message_id == user_message.id &&
            user_message.conversation_id == conversation.id &&
            user_message.customer_id == conversation.customer_id &&
            conversation.current_generation_id == generation.id
        end

        # The proposal is moved rather than dropped: it stops being pending,
        # but the plan the admin approved stays in the transcript instead of
        # vanishing from the conversation the moment it is applied.
        def consume_proposal!(message, generation)
          metadata = message.metadata_json.deep_dup
          applied = metadata.delete("pending_confirmation")
          metadata["applied_proposal"] = applied if applied.present?
          metadata["confirmation_consumed_by_generation_id"] = generation.id
          message.update!(metadata: metadata)
        end

        def confirmation_applied?(result)
          result.respond_to?(:confirmation_applied) && result.confirmation_applied == true
        end

        # True only for a bare yes. Politeness words are dropped first, so
        # "Yes please" and "ok, go ahead" confirm while "yes, and also add X"
        # does not — that carries a new requirement and has to go back to the
        # model. The target resolution below is what makes this safe; this is
        # only the fast path that skips a vendor round-trip.
        #
        # The reply job runs outside the admin's request, so I18n.locale is the
        # application default rather than whatever they were typing in. Every
        # locale's word lists are matched, so a Chinese "确认" is recognised on
        # an English-default worker and vice versa.
        def explicit_confirmation?(body)
          explicit_phrase?(body, tokens: confirmation_tokens, fillers: confirmation_fillers)
        end

        def explicit_rejection?(body)
          explicit_phrase?(body, tokens: rejection_tokens, fillers: rejection_fillers)
        end

        def explicit_phrase?(body, tokens:, fillers:)
          return false if question?(body)

          phrase_variants(normalize(body), fillers).any? { |phrase| tokens_only?(phrase.split(" "), tokens) }
        end

        # Punctuation is stripped before matching, which would otherwise turn a
        # hedge back into a token ("You sure?" -> "sure"). Anything phrased as
        # a question is a request for reassurance, not a decision, so it goes
        # to the model instead of applying or discarding the proposal.
        def question?(body)
          body.to_s.include?("?") || body.to_s.include?("？")
        end

        def normalize(body)
          body.to_s.strip.downcase.gsub(/[[:punct:]]|[，。！？、]/, " ").squeeze(" ").strip
        end

        # Politeness is dropped by word for space-delimited languages and by
        # affix for CJK, which has no word boundaries to split on. A filler is
        # never a lone pronoun: dropping "you" would turn the hedge "you sure"
        # into the token "sure", so politeness phrases like "thank you" are
        # whole entries, stripped as affixes.
        def phrase_variants(normalized, fillers)
          return [] if normalized.blank?

          [without_filler_words(normalized, fillers), without_filler_affixes(normalized, fillers)]
            .reject(&:blank?)
            .uniq
        end

        # True when the phrase is nothing but the decision: every word is
        # consumed by some token, allowing for multi-word tokens such as
        # "go ahead" / "never mind". "ok go ahead" passes; "yes and also add
        # a phone" does not.
        def tokens_only?(words, tokens)
          return false if words.empty?

          reachable = Array.new(words.length + 1, false)
          reachable[0] = true
          words.each_index do |start|
            next unless reachable[start]

            (start...words.length).each do |finish|
              reachable[finish + 1] = true if tokens.include?(words[start..finish].join(" "))
            end
          end
          reachable[words.length]
        end

        def without_filler_words(normalized, fillers)
          normalized.split(" ").reject { |word| fillers.include?(word) }.join(" ")
        end

        def without_filler_affixes(normalized, fillers)
          fillers.reduce(normalized) do |value, filler|
            value.delete_prefix(filler).delete_suffix(filler).strip
          end
        end

        def confirmation_tokens
          @confirmation_tokens ||= words_from("confirmation_tokens")
        end

        def confirmation_fillers
          @confirmation_fillers ||= words_from("confirmation_fillers")
        end

        def rejection_tokens
          @rejection_tokens ||= words_from("rejection_tokens")
        end

        def rejection_fillers
          @rejection_fillers ||= words_from("rejection_fillers")
        end

        def words_from(key)
          I18n.available_locales.flat_map do |locale|
            Array(I18n.t("ai_assistant.assistant.#{key}", locale: locale, default: []))
              .map { |word| word.to_s.strip.downcase }
          end.reject(&:blank?).uniq.freeze
        end

        def proposal_from(message)
          value = message&.metadata_json&.fetch("pending_confirmation", nil)
          value.deep_stringify_keys if value.is_a?(Hash)
        end

        def valid_proposal?(proposal, conversation)
          return false unless proposal.is_a?(Hash)
          return false unless proposal["customer_id"].to_i == conversation.customer_id
          return false unless SUPPORTED_KINDS.include?(proposal["kind"].to_s)

          case proposal["kind"]
          when "operation" then valid_operation_proposal?(proposal, conversation)
          when "flowchart" then valid_flowchart_proposal?(proposal, conversation)
          else false
          end
        end

        def valid_operation_proposal?(proposal, conversation)
          invocation = OperationInvocation.find_by(id: proposal["invocation_id"], customer_id: conversation.customer_id)
          invocation&.awaiting_confirmation? &&
            invocation.customer_id == proposal["customer_id"].to_i &&
            invocation.conversation_id == conversation.id
        end

        def valid_flowchart_proposal?(proposal, conversation)
          return false unless proposal["document"].is_a?(Hash)

          model = Artifact::MODELS[proposal["kind"].to_s]
          return false unless model

          targets = proposal["targets"]
          return false unless targets.is_a?(Array) && targets.present?

          records = locked_target_records(
            model: model,
            targets: targets,
            customer_id: conversation.customer_id
          )
          return false unless records.size == targets.size

          targets.all? do |target|
            next false unless target.is_a?(Hash)
            next false if target["id"].blank? || target["name"].blank? ||
                          target["version_id"].blank?

            record = records[target["id"].to_i]
            record &&
              record.name == target["name"] &&
              proposal.dig("document", "flowchart", "name").to_s == target["name"] &&
              current_version_id(record).to_i == target["version_id"].to_i
          end
        end

        def locked_target_records(model:, targets:, customer_id:)
          ids = targets.filter_map do |target|
            target["id"].to_i if target.is_a?(Hash) && target["id"].present?
          end
          return {} unless ids.size == targets.size && ids.uniq.size == ids.size

          model.unscoped
               .where(customer_id: customer_id, id: ids)
               .order(:id)
               .lock
               .index_by(&:id)
        end

        def current_version_id(record)
          record.respond_to?(:current_line_head_version_id) ?
            record.current_line_head_version_id :
            record.try(:current_version_id)
        end
      end
    end
  end
end
