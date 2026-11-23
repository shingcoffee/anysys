# frozen_string_literal: true

class ActivityGenerator
  # Compile each original access exactly once. An explicit target is a terminal
  # snapshot key, not a new source pin to send through another rewrite pass.
  class ElementBodyRewriter
    def initialize(io_index)
      @io_index = io_index
    end

    def call(element, body)
      @id = element["id"]
      overrides = ElementIoIndex.merge_rename_map_into_overrides(element, @io_index)
      return ordinary_rewrite(body, overrides) unless loop_participant?

      @inputs = CodeGenerators::EmissionRewriter.index_overrides(overrides["inputs"], "override_key", allow_empty: true)
      @outputs = CodeGenerators::EmissionRewriter.index_overrides(overrides["outputs"], "renamed_to")
      @implicit = @io_index.fetch(:loop_reads).fetch(@id, {})
      slots = @io_index.fetch(:loop_body_slots).fetch(@id, {})
      publications = @io_index.fetch(:loop_publications).fetch(@id, {})
      pins = (@io_index[:producer_outputs].fetch(@id, []) + @outputs.keys + @implicit.keys).uniq
      bindings = pins.filter_map do |pin|
        binding = { snapshot: @outputs[pin] || pin, state: slots[pin], read: read_target(pin), publication: publications[pin] }
        next unless provenance_binding?(binding)

        [pin, binding]
      end.to_h
      reads = pins.to_h { |pin| [pin, read_target(pin)] }.select { |pin, target|
        provenance_read?(target) || @inputs.key?(pin)
      }

      FlowchartRuntime::LoopState.rewrite(body, bindings, reads: reads)
    end

    private

    def loop_participant?
      return false unless @io_index[:loop_execution]

      region_ids = @io_index[:loop_region_ids]
      return true if region_ids&.include?(@id)
      return true if @io_index.fetch(:loop_publications, {}).fetch(@id, {}).any?
      @io_index.fetch(:loop_reads, {}).fetch(@id, {}).any? { |_pin, target| provenance_read?(target) }
    end

    def provenance_binding?(binding)
      binding[:state] || binding[:publication] || provenance_read?(binding[:read])
    end

    def provenance_read?(target)
      target.is_a?(Hash) || (target.is_a?(String) && target.start_with?("_loop_"))
    end

    def read_target(pin)
      return @inputs[pin].presence || pin if @inputs.key?(pin)
      return @implicit[pin] if @implicit.key?(pin)

      # Preserve ordinary snapshot resolution outside the planned loop dataflow:
      # explicit/self outputs, then the nearest reachable producer.
      if @io_index[:producer_outputs].fetch(@id, []).include?(pin)
        target = @outputs[pin] || @io_index[:rename_map].dig(@id, pin)
        return target if target
      end
      @io_index[:reachability].fetch(@id, []).reverse_each do |producer|
        next unless @io_index[:producer_outputs].fetch(producer, []).include?(pin)
        return @io_index[:rename_map].dig(producer, pin) || pin
      end
      pin
    end

    def ordinary_rewrite(body, overrides)
      CodeGenerators::EmissionRewriter.call_element(
        body: body,
        element_id: @id,
        io_overrides: overrides,
        rename_map: @io_index[:rename_map],
        reachability: @io_index[:reachability],
        producer_outputs: @io_index[:producer_outputs],
        dominators: @io_index[:dominators] || {},
        topo_index: @io_index[:topo_index] || {}
      )
    end
  end
end
