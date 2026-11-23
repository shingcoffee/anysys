# frozen_string_literal: true

module FlowchartRuntime
  # Per-invocation provenance for pins that participate in loop dataflow.
  # Snapshots keep their ordinary ctx keys; implicit merges select the most
  # recent write that actually ran among their graph predecessors.
  class ExecutedOutputs
    class Error < StandardError; end

    class << self
      def start(ctx, execution)
        validate_execution!(execution)
        initial = execution[:pins].to_h { |pin| [pin, [ctx.key?(pin.to_sym), ctx[pin.to_sym]]] }
        ctx[execution[:key].to_sym] = { clock: 0, writes: {}, initial: initial }
      end

      def ensure_started(ctx, execution)
        validate_execution!(execution)
        key = execution[:key].to_sym
        start(ctx, execution) unless ctx[key].is_a?(Hash) && ctx[key].key?(:writes)
      end

      def publish(ctx, publication, present, value)
        ensure_started(ctx, { key: publication.fetch(:execution), pins: [] })
        registry = registry!(ctx, publication.fetch(:execution))
        registry[:clock] += 1
        registry[:writes][publication.fetch(:producer)] = [registry[:clock], present, value]
      end

      def read(ctx, source)
        return [ctx.key?(source.to_sym), ctx[source.to_sym]] unless source.is_a?(Hash)

        key = source.fetch(:execution).to_sym
        unless ctx[key].is_a?(Hash) && ctx[key].key?(:writes)
          pin = source.fetch(:pin).to_sym
          return [ctx.key?(pin), ctx[pin]]
        end
        registry = ctx[key]
        latest = source.fetch(:candidates).filter_map { |candidate| registry[:writes][candidate] }.max_by(&:first)
        latest ? latest.drop(1) : registry[:initial].fetch(source.fetch(:pin), [false, nil])
      end

      # Preserve Hash access semantics for [], fetch, dig and key? without
      # turning an absent value into a present nil or treating false as missing.
      def read_context(ctx, source)
        present, value = read(ctx, source)
        present ? { source.fetch(:pin).to_sym => value } : {}
      end

      def fetch(ctx, pin, candidates:, execution: "_loop_io")
        _present, value = read(ctx, { execution: execution, candidates: Array(candidates), pin: pin.to_s })
        value
      end

      def initialize_slot(ctx, slot, source)
        present, value = read(ctx, source)
        present ? ctx[slot.to_sym] = value : ctx.delete(slot.to_sym)
      end

      def export(ctx, publication, slot)
        publish(ctx, publication, ctx.key?(slot.to_sym), ctx[slot.to_sym])
      end

      private

      def validate_execution!(execution)
        unless execution.is_a?(Hash) && execution[:key].to_s != "" && execution[:pins].is_a?(Array)
          raise Error, "execution key and pins are required"
        end
      end

      def registry!(ctx, execution_key)
        registry = ctx[execution_key.to_sym]
        return registry if registry.is_a?(Hash) && registry.key?(:writes)

        raise Error, "loop provenance has not been started"
      end
    end
  end
end
