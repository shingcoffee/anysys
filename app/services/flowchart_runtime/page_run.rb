# frozen_string_literal: true

module FlowchartRuntime
  # Runs a page's flowchart for one submission. The flowchart does all the
  # work — validation, writes, side effects, the outcome — inside one
  # savepoint that it shares with the module handoff the caller begins from
  # the block, so a refusal anywhere rolls everything back. Password checks
  # are journaled on that savepoint (Authentication::PasswordEffects).
  #
  # The page record is the submitted record when the flowchart saved it, else
  # the record of the page's entity it saved in its place. A flowchart that
  # sets ctx[:discard_record] (registration's anti-enumeration answer) keeps
  # what else it wrote, but hands no record over and removes the page's new
  # record if it saved it; a record it found and reused is never removed.
  class PageRun
    include Loggable

    Result = Data.define(:entry, :outcome, :handed_off, :errors, :field_errors) do
      def ok? = errors.empty?
    end

    # Raised from the block to refuse the submission with its message.
    class Refused < StandardError; end

    HANDOFF_ERRORS = [
      FeatureModules::ModuleNotEnabled, FeatureModules::InputContractViolation, FeatureModules::RegistrationError, Refused
    ].freeze

    # The block receives (entry, outcome) and returns whether it began a handoff.
    def self.call(flowchart:, context:, &handoff) = new(flowchart, context, handoff).call

    def initialize(flowchart, context, handoff)
      @flowchart = flowchart
      @context = context
      @handoff = handoff
      @timing_started_at = nil
    end

    def call
      result = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        ::Authentication::PasswordEffects.transaction(customer_id: @context.customer_id) { result = run }
        raise ActiveRecord::Rollback unless result.ok?
      end
      result
    rescue StandardError => e
      log_error "Page #{@context.page.id} flowchart #{@flowchart.id} raised #{e.class}: #{e.message}"
      log_error Array(e.backtrace).first(10).join("\n")
      refused([I18n.t("common.errors.dynamic.activity_execution_failed")])
    ensure
      # Registration starts the clock before its email lookup; the wait runs
      # once the savepoint has released its locks, whatever the outcome.
      ::Authentication::UniformTiming.pad(@timing_started_at)
    end

    private

    def run
      log_info "Submitting page #{@context.page.id} (#{@context.target.mode}) through flowchart #{@flowchart.id}"
      trace = ActivityTracer.new(@flowchart).call(@context.to_ctx, trace: false)
      ctx = trace.ctx.is_a?(Hash) ? trace.ctx : {}
      @timing_started_at = ctx[:uniform_timing_started_at]
      return refusal(ctx) unless trace.success?

      outcome = ctx[:submission_outcome].to_h.deep_stringify_keys
      entry = ctx[:discard_record] == true ? discard : page_record(ctx)
      handed_off = @handoff ? @handoff.call(entry, outcome) == true : false
      Result.new(entry: entry, outcome: outcome, handed_off: handed_off, errors: [], field_errors: [])
    rescue *HANDOFF_ERRORS => e
      refused([e.message])
    end

    def page_record(ctx)
      record = @context.target.record
      return record if record.persisted?

      contract_model = ctx[:contract].model if ctx[:contract].respond_to?(:model)
      [ctx[:model], contract_model].find do |entry|
        entry.is_a?(EntityEntry) && entry.persisted? && entry.entity_id == record.entity_id &&
          entry.customer_id.to_s == record.customer_id.to_s
      end
    end

    def discard
      record = @context.target.record
      record.destroy! if @context.target.create? && record.persisted?
      nil
    end

    def refusal(ctx)
      log_error "Page #{@context.page.id} flowchart #{@flowchart.id} refused the submission"
      refused(Errors.collect(ctx).presence || [I18n.t("common.errors.dynamic.activity_execution_failed")],
              Errors.fields(ctx))
    end

    def refused(errors, field_errors = [])
      Result.new(entry: nil, outcome: {}, handed_off: false, errors: errors, field_errors: field_errors)
    end
  end
end
