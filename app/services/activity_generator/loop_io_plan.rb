# frozen_string_literal: true

class ActivityGenerator
  # Loop state is a separate namespace from element output snapshots. A loop is
  # one producer exporting its final state (including zero trips) only when it
  # executes. Entry/merge reads list eligible producers; execution provenance,
  # not graph/branch ordering, selects their value. Explicit aliases are terminal.
  class LoopIoPlan
    def initialize(elements:, topology:, outputs:, scope:)
      @elements = elements.index_by { |element| element["id"] }
      @topology = topology
      @outputs = outputs
      @scope = scope
      @owners = topology.regions.each_with_object({}) do |(header, region), owners|
        region[:body_ids].each { |id| owners[id] = header }
      end
    end

    def build
      @slots = build_slots
      @pins = @slots.values.flat_map(&:keys).uniq
      @execution = { key: "_loop_io", pins: @pins } if @pins.any?
      body_slots = @elements.keys.to_h { |id| [id, @slots.fetch(@owners[id] || id, {})] }
      {
        loop_execution: @execution,
        loop_initializers: build_initializers,
        loop_body_slots: body_slots,
        loop_reads: build_reads(body_slots),
        loop_publications: build_publications,
        loop_exports: @slots.to_h { |id, slots| [id, slots.to_h { |pin, slot| [slot, publication(id, pin)] }] },
        loop_region_ids: region_ids
      }
    end

    private

    def region_ids
      ids = Set.new
      @topology.regions.each do |header, region|
        ids << header
        ids.merge(region[:body_ids])
      end
      ids
    end

    def build_slots
      @topology.regions.to_h do |header, region|
        pins = region[:body_ids].flat_map { |id| @outputs.fetch(id, []) }.uniq.grep_v(ElementIoIndex::RUNTIME_PIN)
        [header, pins.to_h { |pin| [pin, slot_key(header, pin)] }]
      end
    end

    def slot_key(header, pin)
      "_loop_#{ident(header_ident(header))}_#{ident(pin)}"
    end

    def header_ident(header)
      header_idents.fetch(header)
    end

    def header_idents
      @header_idents ||= begin
        deriver = NameDeriver.new
        used = {}
        @topology.regions.keys.to_h do |id|
          [id, deriver.derive_method_name(@elements.fetch(id), used)]
        end
      end
    end

    def ident(value)
      s = value.to_s.gsub(/[^a-zA-Z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      s = "x#{s}" if s.match?(/\A\d/)
      s.empty? ? "pin" : s
    end

    def build_initializers
      @slots.to_h do |header, slots|
        explicit = input_overrides(header)
        [header, slots.to_h { |pin, slot| [slot, explicit.key?(pin) ? explicit[pin].presence || pin : upstream_source(header, pin)] }]
      end
    end

    def build_reads(body_slots)
      @elements.keys.to_h do |id|
        bindings = @pins.filter_map do |pin|
          slot = body_slots[id][pin]
          next [pin, slot] if slot
          consumer = @owners[id] || id
          next unless predecessors(consumer).any? { |producer| @slots.dig(producer, pin) }

          [pin, upstream_source(consumer, pin, include_self: true)]
        end.to_h
        [id, bindings]
      end
    end

    def input_overrides(id)
      CodeGenerators::EmissionRewriter.index_overrides(@elements[id].dig("properties", "io_overrides", "inputs"), "override_key", allow_empty: true)
    end

    def publication(id, pin)
      { execution: @execution.fetch(:key), producer: "#{id}:#{pin}" }
    end

    def build_publications
      @elements.keys.to_h do |id|
        pins = @outputs.fetch(id, []) & @pins
        [id, pins.to_h { |pin| [pin, publication(id, pin)] }]
      end
    end

    def upstream_source(id, pin, include_self: false)
      eligible = include_self ? [id, *predecessors(id)] : predecessors(id)
      candidates = eligible.filter_map do |producer|
        publication(producer, pin)[:producer] if @slots.dig(producer, pin) || @outputs.fetch(producer, []).include?(pin)
      end
      { execution: @execution.fetch(:key), candidates: candidates, pin: pin }
    end

    # Collapse every body into its header for entry and exit bindings. Keeping
    # the body writers in this graph would select a future/unexecuted snapshot.
    def predecessors(id)
      @predecessors ||= {}
      @predecessors[id] ||= begin
        reverse = collapsed_reverse_graph
        seen = Set.new([id])
        queue = reverse[id].dup
        order = []
        while (current = queue.shift)
          next unless seen.add?(current)
          order << current
          queue.concat(reverse[current])
        end
        order
      end
    end

    def collapsed_reverse_graph
      @collapsed_reverse_graph ||= Hash.new { |hash, key| hash[key] = [] }.tap do |reverse|
        @topology.dataflow_connections.each do |edge|
          next if @owners.key?(edge["from"]) || @owners.key?(edge["to"])
          reverse[edge["to"]] << edge["from"]
        end
      end
    end
  end
end
