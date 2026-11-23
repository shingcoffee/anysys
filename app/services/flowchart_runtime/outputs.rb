# frozen_string_literal: true

module FlowchartRuntime
  # Presence-based selection of a ctx value at a merge. Generated reads call
  # +latest+ with candidate keys in latest-writer-first order; the first key
  # that is present (including an explicit +nil+) is the write that ran.
  module Outputs
    module_function

    def latest(ctx, *keys)
      keys.each do |key|
        return ctx[key] if ctx.key?(key)
      end
      nil
    end

    # A one-key Hash so `dig` / `fetch` (with defaults) / `key?` keep Hash
    # semantics after the rewriter replaces only the `ctx` receiver.
    def view(ctx, pin, *keys)
      pin = pin.to_sym
      keys.each do |key|
        return { pin => ctx[key] } if ctx.key?(key)
      end
      {}
    end
  end
end
