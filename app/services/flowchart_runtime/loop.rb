# frozen_string_literal: true

module FlowchartRuntime
  # Iteration-state helper for generated loop headers. One short ctx key holds
  # the header's cursor; leave removes it so a reused ctx cannot leak between
  # invocations.
  module Loop
    class Error < StandardError; end

    module_function

    def enter(ctx, key, execution: nil, pins: [], initializers: {}, state: nil)
      raise Error, "loop key required" if key.nil? || key.to_s.strip.empty?

      name = key.to_sym
      unless ctx[name]
        ExecutedOutputs.ensure_started(ctx, { key: execution, pins: Array(pins) }) if execution
        (initializers || {}).each do |slot, source|
          ExecutedOutputs.initialize_slot(ctx, slot, source)
        end
        ctx[name] = if block_given?
          yield
        else
          state || {}
        end
      end
      ctx[name]
    end

    def leave(ctx, key, exports = {})
      raise Error, "loop key required" if key.nil? || key.to_s.strip.empty?

      (exports || {}).each do |slot, publication|
        ExecutedOutputs.export(ctx, publication, slot)
      end
      ctx.delete(key.to_sym)
      nil
    end

    # Successful leave, then fail the run. Used when maxIterations is reached
    # while the loop would otherwise continue (condition still true, or items
    # remain).
    def fail_limit(ctx, key, max:, exports: {})
      leave(ctx, key, exports)
      Step.fail(ctx, :loop_limit, max: max)
    end
  end
end
