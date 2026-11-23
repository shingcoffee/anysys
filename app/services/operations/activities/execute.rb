# frozen_string_literal: true

module Operations
  module Activities
    class Execute < Trailblazer::Activity::Railway
      step :resolve
      step :authorize
      step :replay
      step :validate_schema
      step :validate_semantics
      step :plan_and_snapshot
      step :gate
      step :perform

      def self.call(operation:, input:, context:)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        _signal, (ctx, *) = super([
          { operation: operation, input: input, context: context, started_at: started_at },
          {}
        ])
        record!(ctx)
        ctx.fetch(:outcome)
      end

      def resolve(ctx, operation:, **)
        klass = operation.is_a?(Class) ? operation : Operations.for(operation)
        unless klass.is_a?(Class) && klass < Operations::Base
          ctx[:outcome] = unknown_outcome(ctx)
          return false
        end

        ctx[:operation_class] = klass
        ctx[:operation_key] = klass.key
        true
      rescue ArgumentError, NoMethodError
        ctx[:outcome] = unknown_outcome(ctx)
        false
      end

      def authorize(ctx, context:, operation_class:, **)
        unless Authorization.allowed?(actor: context.actor, customer: context.customer) &&
               operation_class.available?(context)
          ctx[:outcome] = Outcome.forbidden(
            operation: operation_class.key,
            violations: [Violation.new(code: "permission.denied")]
          )
          return false
        end

        true
      end

      def replay(ctx, context:, operation_class:, input:, **)
        return true if operation_class.read_only? || context.idempotency_key.blank?

        digest = self.class.input_digest(input)
        ctx[:input_digest] = digest
        existing = OperationInvocation.find_by(
          customer_id: context.customer.id,
          idempotency_key: context.idempotency_key
        )
        return true unless existing

        if existing.input_digest == digest
          ctx[:outcome] = Outcome.from_stored_result(existing.result, invocation: existing, replayed: true)
          ctx[:replayed] = true
          return false
        end

        ctx[:skip_record] = true
        ctx[:outcome] = Outcome.invalid(
          operation: operation_class.key,
          violations: [Violation.new(code: "idempotency.key_reused")]
        )
        false
      end

      def validate_schema(ctx, operation_class:, input:, context:, **)
        self.class.guarded(ctx, operation_class) do
          violations, normalized = operation_class.input_schema(context).validate(input)
          ctx[:normalized] = normalized
          next true if violations.empty?

          ctx[:outcome] = Outcome.invalid(operation: operation_class.key, violations: violations)
          false
        end
      end

      def validate_semantics(ctx, operation_class:, context:, normalized:, **)
        self.class.guarded(ctx, operation_class) do
          instance = operation_class.new(context: context)
          ctx[:instance] = instance
          violations = Array.wrap(instance.validate(normalized))
          next true if violations.empty?

          ctx[:outcome] = Outcome.invalid(operation: operation_class.key, violations: violations)
          false
        end
      end

      def plan_and_snapshot(ctx, instance:, normalized:, operation_class:, **)
        self.class.guarded(ctx, operation_class) do
          ctx[:plan] = instance.plan(normalized)
          ctx[:snapshot] = instance.snapshot(normalized)
          true
        end
      end

      # Validation and planning run before perform_atomically. An exception
      # there still comes back as an outcome, never as a raw error in a tool
      # payload.
      def self.guarded(ctx, operation_class)
        yield
      rescue StandardError => e
        Rails.logger.error([e.class, e.message, *e.backtrace].join("\n"))
        ctx[:outcome] = Outcome.failed(operation: operation_class.key, violations: [Violation.new(code: "internal.error")])
        false
      end

      def gate(ctx, operation_class:, context:, **)
        if context.dry_run
          ctx[:outcome] = Outcome.dry_run(operation: operation_class.key, plan: ctx[:plan])
          return false
        end

        if operation_class.confirmation == :always && !context.confirmed
          invocation = create_invocation!(ctx, status: "awaiting_confirmation")
          ctx[:invocation] = invocation
          ctx[:outcome] = Outcome.confirmation_required(
            operation: operation_class.key,
            plan: ctx[:plan],
            invocation: invocation
          )
          return false
        end

        true
      end

      def perform(ctx, context:, instance:, normalized:, operation_class:, **)
        ctx[:outcome] = self.class.perform_atomically(context: context, operation_key: operation_class.key) do
          instance.perform(normalized)
        end
        ctx[:outcome].ok?
      end

      # Errors raised by `around_write` itself propagate to the caller. Errors
      # raised by the operation become outcomes, and any non-ok outcome rolls
      # the write back. `requires_new` matters: callers such as the assistant's
      # generation guard already hold a transaction, and a Rollback inside a
      # joined transaction is swallowed without undoing anything.
      def self.perform_atomically(context:, operation_key:)
        outcome = nil
        context.around_write.call do
          context.customer.with_lock(requires_new: true) do
            outcome = Current.with_customer(context.customer) { rescue_into_outcome(operation_key) { yield } }
            raise ActiveRecord::Rollback unless outcome.ok?
          end
        end
        outcome
      end

      def self.rescue_into_outcome(operation_key)
        result = yield
        raise TypeError, "#{operation_key}#perform returned #{result.class}, not an Operations::Outcome" unless result.is_a?(Outcome)

        result
      rescue ActiveRecord::RecordInvalid => e
        Outcome.invalid(
          operation: operation_key,
          violations: [Violation.new(code: "domain.invalid", details: { "errors" => e.record.errors.full_messages })]
        )
      rescue StandardError => e
        Rails.logger.error([e.class, e.message, *e.backtrace].join("\n"))
        Outcome.failed(operation: operation_key, violations: [Violation.new(code: "internal.error")])
      end

      def self.input_digest(input)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(input)))
      end

      def self.canonicalize(value)
        case value
        when Hash
          value.to_h.transform_keys(&:to_s).sort.to_h.transform_values { |item| canonicalize(item) }
        when Array
          value.map { |item| canonicalize(item) }
        else
          value
        end
      end

      def self.record!(ctx)
        return if ctx[:replayed] || ctx[:skip_record]
        return unless ctx[:operation_class]
        return if ctx[:operation_class].read_only?
        return if ctx[:outcome]&.status == "dry_run"

        invocation = ctx[:invocation]
        attrs = invocation_attributes(ctx)
        if invocation
          invocation.update!(attrs.slice(:duration_ms, :result, :violations, :status, :plan, :snapshot, :input))
          ctx[:outcome].invocation ||= invocation
        else
          ctx[:invocation] = create_audit!(attrs)
          ctx[:outcome].invocation = ctx[:invocation] if ctx[:outcome]
        end
      end

      # Two overlapping calls with one key can both pass the replay lookup.
      # The second still gets its audit row, without the key the first holds.
      def self.create_audit!(attrs)
        OperationInvocation.create!(attrs)
      rescue ActiveRecord::RecordNotUnique
        OperationInvocation.create!(attrs.merge(idempotency_key: nil))
      end

      def self.invocation_attributes(ctx)
        context = ctx[:context]
        outcome = ctx[:outcome]
        {
          customer_id: context.customer.id,
          user_id: id_of(context.actor),
          operation: ctx[:operation_key] || ctx[:operation_class].key,
          operation_version: ctx[:operation_class].version,
          channel: context.channel,
          status: invocation_status(outcome),
          idempotency_key: replayable?(outcome) ? context.idempotency_key.presence : nil,
          input_digest: ctx[:input_digest] || input_digest(ctx[:input]),
          input: ctx[:normalized] || canonicalize(ctx[:input]),
          plan: ctx[:plan] || [],
          snapshot: ctx[:snapshot] || {},
          result: outcome&.as_stored_result || {},
          violations: Array(outcome&.violations).map(&:as_json),
          conversation_id: id_of(context.conversation),
          generation_id: id_of(context.generation),
          duration_ms: duration_ms(ctx[:started_at])
        }
      end

      # Only a call that was carried out (or parked) holds its idempotency key.
      # A rejected or failed call is not remembered, so the same call can run
      # again once whatever it was missing exists.
      def self.replayable?(outcome)
        outcome.nil? || outcome.ok?
      end

      def self.invocation_status(outcome)
        return "awaiting_confirmation" if outcome&.status == "confirmation_required"

        outcome&.status || "failed"
      end

      def self.id_of(value)
        return if value.nil?

        value.respond_to?(:id) ? value.id : value
      end

      def self.duration_ms(started_at)
        return unless started_at

        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      end

      private

      def unknown_outcome(_ctx)
        available = Operations.keys.map(&:to_s)
        Outcome.invalid(
          operation: nil,
          violations: [Violation.new(code: "operation.unknown", details: { "available" => available })]
        )
      end

      def create_invocation!(ctx, status:)
        self.class.create_audit!(
          self.class.invocation_attributes(ctx).merge(
            status: status,
            result: {},
            violations: []
          )
        )
      end
    end
  end
end
