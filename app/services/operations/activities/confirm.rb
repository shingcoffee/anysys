# frozen_string_literal: true

module Operations
  module Activities
    class Confirm < Trailblazer::Activity::Railway
      step :require_pending
      step :resolve
      step :authorize
      step :revalidate
      step :apply

      def self.call(invocation:, context:)
        _signal, (ctx, *) = super([{ invocation: invocation, context: context }, {}])
        ctx.fetch(:outcome)
      end

      def self.supersede!(invocation)
        invocation.update!(status: "superseded")
        invocation
      end

      def self.decline!(invocation, actor:)
        invocation.update!(
          status: "declined",
          confirmed_by_id: Execute.id_of(actor),
          confirmed_at: Time.current
        )
        invocation
      end

      # A proposal parked inside a conversation is approved from that
      # conversation only; one parked without a conversation by any caller
      # authorized for its customer.
      def require_pending(ctx, invocation:, context:, **)
        same_thread = invocation.conversation_id.nil? || invocation.conversation_id == context.conversation&.id
        unless invocation.awaiting_confirmation? && invocation.customer_id == context.customer.id && same_thread
          ctx[:outcome] = Outcome.invalid(
            operation: invocation.operation,
            violations: [Violation.new(code: "proposal.not_pending")]
          )
          return false
        end

        true
      end

      def resolve(ctx, invocation:, **)
        klass = Operations.for(invocation.operation)
        unless klass.is_a?(Class) && klass < Operations::Base
          ctx[:outcome] = Outcome.invalid(
            operation: invocation.operation,
            violations: [Violation.new(code: "operation.unknown", details: { "available" => Operations.keys.map(&:to_s) })]
          )
          return false
        end

        if klass.version != invocation.operation_version
          ctx[:outcome] = Outcome.invalid(
            operation: invocation.operation,
            violations: [Violation.new(code: "operation.version_changed")]
          )
          return false
        end

        ctx[:operation_class] = klass
        true
      rescue ArgumentError, NoMethodError
        ctx[:outcome] = Outcome.invalid(
          operation: invocation.operation,
          violations: [Violation.new(code: "operation.unknown", details: { "available" => Operations.keys.map(&:to_s) })]
        )
        false
      end

      def authorize(ctx, context:, operation_class:, invocation:, **)
        unless Authorization.allowed?(actor: context.actor, customer: context.customer) &&
               operation_class.available?(context)
          ctx[:outcome] = Outcome.forbidden(
            operation: invocation.operation,
            violations: [Violation.new(code: "permission.denied")]
          )
          return false
        end

        true
      end

      def revalidate(ctx, operation_class:, invocation:, context:, **)
        return true if Execute.guarded(ctx, operation_class) { checked_input(ctx, operation_class, invocation, context) }

        if ctx[:outcome]&.status == "failed"
          ctx[:outcome].invocation = invocation
          finish_row!(invocation, context, ctx[:outcome])
        end
        false
      end

      # The staleness check runs under the same customer lock as the write, so
      # nothing can change the target between the check and the perform.
      def apply(ctx, invocation:, context:, instance:, normalized:, operation_class:, **)
        outcome = Execute.perform_atomically(context: confirmed_context(context), operation_key: operation_class.key) do
          if instance.stale?(invocation.snapshot)
            Outcome.conflict(operation: invocation.operation, violations: [Violation.new(code: "conflict.version_changed")])
          else
            instance.perform(normalized)
          end
        end

        finish_row!(invocation, context, outcome)
        outcome.invocation = invocation
        ctx[:outcome] = outcome
        outcome.ok?
      end

      private

      def checked_input(ctx, operation_class, invocation, context)
        violations, normalized = operation_class.input_schema(context).validate(invocation.input)
        if violations.any?
          finish_row!(invocation, context, Outcome.invalid(operation: invocation.operation, violations: violations))
          ctx[:outcome] = Outcome.invalid(operation: invocation.operation, violations: violations, invocation: invocation)
          return false
        end

        instance = operation_class.new(context: confirmed_context(context))
        # A target that moved since parking can make the parked changes fail
        # validation (an attribute to remove is already gone). That is still a
        # conflict, so staleness is checked first. apply re-checks it under the
        # customer lock.
        if instance.stale?(invocation.snapshot)
          outcome = Outcome.conflict(operation: invocation.operation, invocation: invocation,
                                     violations: [Violation.new(code: "conflict.version_changed")])
          finish_row!(invocation, context, outcome)
          ctx[:outcome] = outcome
          return false
        end

        semantic = Array.wrap(instance.validate(normalized))
        if semantic.any?
          # A proposal that no longer validates because its target moved is a
          # conflict, not a bad payload: the admin should be asked to request
          # the change again.
          builder = semantic.any? { |violation| violation.code.start_with?("conflict.") } ? :conflict : :invalid
          outcome = Outcome.public_send(builder, operation: invocation.operation, violations: semantic, invocation: invocation)
          finish_row!(invocation, context, outcome)
          ctx[:outcome] = outcome
          return false
        end

        ctx[:instance] = instance
        ctx[:normalized] = normalized
        true
      end

      def confirmed_context(context)
        Context.new(
          customer: context.customer,
          actor: context.actor,
          channel: context.channel,
          conversation: context.conversation,
          generation: context.generation,
          idempotency_key: context.idempotency_key,
          dry_run: false,
          confirmed: true,
          around_write: context.around_write
        )
      end

      def finish_row!(invocation, context, outcome)
        invocation.update!(
          status: outcome.status,
          result: outcome.as_stored_result,
          violations: Array(outcome.violations).map(&:as_json),
          confirmed_by_id: Execute.id_of(context.actor),
          confirmed_at: Time.current
        )
      end
    end
  end
end
