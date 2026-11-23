# frozen_string_literal: true

module AiAssistant
  module Activities
    # Shared guard + resolution for every activity that names a conversation.
    #
    # The security invariant is here rather than in each activity: a thread is
    # only ever reached through AiAssistant::Conversation.resolve, which
    # constrains the lookup to the caller's own (customer, user) pair. No
    # activity may take an id straight to `find`.
    #
    # Preflight supplies the Result shape, `fail_result` and the tenant
    # module gate. Its vendor throttle and provider-configured check are
    # deliberately NOT part of #preflight_failure here: listing, naming,
    # archiving and deleting a thread cost no vendor call, a tenant whose
    # provider was switched off still has to be able to tidy up the threads it
    # already has, and a burst of renames must not spend the chat budget that
    # AiAssistant::Limits reserves for actual turns.
    module ConversationScoped
      include AiAssistant::Activities::Preflight

      # @return [Preflight::Result, nil]
      def preflight_failure
        return fail_result(422, contract_errors) unless contract_valid?

        disabled_failure
      end

      # 404, not 403: the caller learns nothing about whether the id exists in
      # someone else's history.
      def not_found_failure
        fail_result(404, [ I18n.t("ai_assistant.errors.conversation_not_found") ])
      end

      # A blank id means "the current thread", which is right for a composer
      # POST that carries no thread. May create the thread it returns.
      def resolve_conversation(id)
        AiAssistant::Conversation.resolve(customer: customer, user: user, id: id)
      end

      # Rename / archive / delete always name their target. Reading a blank id
      # as "the current thread" would let an id-less request mutate — or
      # destroy — a thread the caller never asked for.
      def resolve_named_conversation(id)
        return nil if id.blank?

        resolve_conversation(id)
      end

      # Same scoping as #resolve_conversation but never writes. Stop and the
      # round-cap precheck run before the request is known to be allowed, so
      # they must not materialise a thread as a side effect.
      def existing_conversation(id)
        scope = AiAssistant::Conversation.owned_by(customer: customer, user: user)
        return running_or_latest(scope) if id.blank?

        scope.find_by(id: id)
      end

      # An id-less stop means "whatever is running". That is usually the most
      # recently active thread, but not always: a reply still streaming into an
      # older thread would otherwise be left running while a newer, idle thread
      # was cancelled in its place.
      #
      # The status has to be joined, not inferred from current_generation_id:
      # cancelling or finishing a turn leaves that id in place, so a thread
      # that merely once had a generation would shadow the one that has a
      # generation now. Archived threads are excluded for the same reason they
      # are not candidates for "the current thread" — an id-less request must
      # not act on a thread the user has put away.
      def running_or_latest(scope)
        scope.active
             .joins(:current_generation)
             .where(ai_assistant_generations: { status: AiAssistant::Generation::ACTIVE_STATUSES })
             .recent_first.first ||
          scope.active.recent_first.first
      end

      # A thread is capped so the replayed history stays bounded and the
      # context stays coherent; the admin escapes it with StartConversation.
      # Shared with every activity that spends a turn — a send and a
      # regenerate both cost the same vendor calls, so they must not disagree
      # about whether a thread is spent.
      def exhausted?(conversation)
        return false if conversation.nil?

        AiAssistant::Limits.turns_exhausted?(conversation.user_turns)
      end

      def conversation_limit_failure
        fail_result(
          429,
          [ I18n.t("ai_assistant.errors.conversation_limit", count: AiAssistant::Limits::MAX_TURNS) ],
          error_code: "conversation_limit"
        )
      end

      # Sidebar refresh. Lives on the user stream, so it survives the deletion
      # of the thread that triggered it.
      def broadcast_conversations(current_id: nil)
        AiAssistant::Stream.broadcast_conversations(
          customer: customer,
          user: user,
          current_id: current_id
        )
      end

      # Most of these activities take no user input beyond an id they resolve
      # through the scope above; RenameConversation overrides with a contract.
      def contract_valid?
        true
      end

      def contract_errors
        []
      end
    end
  end
end
