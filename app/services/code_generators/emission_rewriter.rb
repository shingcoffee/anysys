# frozen_string_literal: true

require "prism"
require_relative "io_extractor/body_analyzer"

module CodeGenerators
  # EmissionRewriter: element-level body source rewriter that applies
  # io_overrides to generated Ruby bodies.
  #
  # .call_element resolves reads through:
  #
  #   1. Explicit input override (inputs entry with non-empty override_key).
  #   2. Tombstone ("" override_key) — read stays as ctx[:pin].
  #   3. Candidate producers = the reader itself when it writes the pin, then
  #      upstream writers of the pin, latest first by topological index.
  #      0 candidates → no rewrite; 1 → that candidate's effective key;
  #      several → the latest candidate's key when it dominates the reader
  #      and is not the reader, otherwise FlowchartRuntime::Outputs.latest.
  #
  # Additional inputs:
  #   * element_id       — the id of the consuming element (reader).
  #   * rename_map       — { producer_id => { pin => renamed_to } } from
  #                        each producer's outputs overrides / ConflictResolver.
  #   * reachability     — { element_id => [ancestor_ids_in_flow_order] }
  #                        where the LAST id is the NEAREST producer.
  #   * producer_outputs — { producer_id => [pins_that_producer_writes] }.
  #   * dominators       — { element_id => Set of dominating element ids }.
  #   * topo_index       — { element_id => integer topological index }.
  class EmissionRewriter
    # Splicer: shared body-editing primitives used by ElementCall. Kept as a
    # module so callers can access @body via their own instance state.
    module Splicer
      # Applies the collected edits to `body`. Sorting descending by start
      # means later (higher-offset) edits don't shift earlier edits' offsets.
      # The by_start dedupe keeps the first edit recorded for a given span,
      # which is how writes win over reads for op-assigns (writes are built
      # first by the caller).
      def apply_edits(body, edits)
        by_start = {}
        edits.each { |e| by_start[e[:start]] ||= e }
        sorted = by_start.values.sort_by { |e| -e[:start] }
        result = body.b.dup
        sorted.each { |e| result[e[:start], e[:length]] = e[:replacement].to_s.b }
        result.force_encoding(body.encoding)
      end

      def edit(node, target)
        { start: node[:start], length: node[:length], replacement: "ctx[:#{target}]" }
      end

      def splice(node, replacement)
        { start: node[:start], length: node[:length], replacement: replacement }
      end
    end

    def self.call_element(body:, element_id:, io_overrides:, rename_map:, reachability:,
                          producer_outputs:, dominators: {}, topo_index: {})
      ElementCall.new(
        body:              body,
        element_id:        element_id,
        io_overrides:      io_overrides || {},
        rename_map:        rename_map || {},
        reachability:      reachability || {},
        producer_outputs:  producer_outputs || {},
        dominators:        dominators || {},
        topo_index:        topo_index || {}
      ).call
    end

    # A `target` is spliced into generated Ruby as `ctx[:#{target}]`. The
    # full surface is bounded to: valid Ruby identifier and not a Ruby
    # reserved word. Anything else would inject arbitrary Ruby into the
    # rewriter's output — io_overrides comes from user JSON via the
    # flowchart UI, so the input is untrusted.
    def self.safe_target?(target)
      s = target.to_s
      return false if s.empty?
      return false unless Shared::IdentifierSanitizer::IDENT_RE.match?(s)
      return false if Shared::IdentifierSanitizer::RUBY_RESERVED.include?(s)
      true
    end

    # Shared hash-builder for io_overrides entries.
    #
    # list         — array of override entries (string- or symbol-keyed).
    # key          — which target field to pull ("renamed_to" or
    #                "override_key").
    # allow_empty  — when true, empty-string targets are kept as explicit
    #                tombstones (element-level input overrides). When false,
    #                the entry is skipped when target == pin or target is
    #                blank.
    def self.index_overrides(list, key, allow_empty: false)
      out = {}
      Array(list).each do |entry|
        pin = entry["pin"] || entry[:pin]
        next if pin.nil?
        target_present = entry.key?(key.to_s) || entry.key?(key.to_sym)
        next unless target_present
        target = entry[key.to_s] || entry[key.to_sym]
        target_str = target.to_s
        if allow_empty
          # Tombstone (target == "") is always allowed; otherwise the value
          # MUST be a safe identifier to be spliced into ctx[:#{target}].
          if target_str.empty? || safe_target?(target_str)
            out[pin.to_s] = target_str
          end
        else
          next if target.nil? || target == pin
          next unless safe_target?(target_str)
          out[pin.to_s] = target_str
        end
      end
      out
    end

    class ElementCall
      include Splicer

      TOMBSTONE = ""

      def initialize(body:, element_id:, io_overrides:, rename_map:, reachability:,
                     producer_outputs:, dominators:, topo_index:)
        @body             = body
        @element_id       = element_id.to_s
        @io_overrides     = io_overrides
        @rename_map       = rename_map
        @reachability     = reachability
        @producer_outputs = producer_outputs
        @dominators       = dominators
        @topo_index       = topo_index
      end

      def call
        return @body if @body.nil? || @body.empty?

        input_map  = EmissionRewriter.index_overrides(@io_overrides["inputs"]  || @io_overrides[:inputs],  "override_key", allow_empty: true)
        @output_map = EmissionRewriter.index_overrides(@io_overrides["outputs"] || @io_overrides[:outputs], "renamed_to")

        ast = IoExtractor::BodyAnalyzer.call(@body)
        edits = []

        ast[:writes].each do |w|
          target = @output_map[w[:pin]]
          edits << edit(w, target) if target
        end

        ast[:reads].each do |r|
          next if r[:implied]

          replacement = bracket_read_replacement(r[:pin], input_map)
          edits << splice(r, replacement) if replacement
        end

        collect_method_read_edits(edits, input_map)
        apply_edits(@body, edits)
      end

      private

      METHOD_READS = %i[dig fetch key?].freeze

      # Returns the Ruby expression to splice over a `ctx[:pin]` span, or nil
      # if no rewrite is needed.
      def bracket_read_replacement(pin, input_map)
        decision = resolve_pin(pin, input_map)
        return nil if decision == :none || decision == :tombstone
        return ctx_access(decision[:key]) if decision[:kind] == :key

        latest_access(decision[:keys])
      end

      # OperandConverter / CtxReader emit `ctx.dig(:pin, …)`, `ctx.fetch(:pin …)`
      # and `ctx.key?(:pin)`. BodyAnalyzer's public reads stay `ctx[:sym]` only
      # (IoExtractor depends on that), so these forms are resolved here with
      # Prism byte-exact spans — the same receiver/symbol split LoopState uses.
      def collect_method_read_edits(edits, input_map)
        root = Prism.parse(@body).value
        return unless root

        queue = [root]
        while (node = queue.pop)
          queue.concat(node.compact_child_nodes)
          next unless node.is_a?(Prism::CallNode) && METHOD_READS.include?(node.name)
          next unless ctx_receiver?(node.receiver)

          key_node = node.arguments&.arguments&.first
          next unless key_node.is_a?(Prism::SymbolNode)

          pin = key_node.unescaped
          decision = resolve_pin(pin, input_map)
          next if decision == :none || decision == :tombstone

          if decision[:kind] == :key
            next if decision[:key] == pin

            loc = key_node.location
            edits << splice({ start: loc.start_offset, length: loc.length }, ":#{decision[:key]}")
          else
            loc = node.receiver.location
            edits << splice({ start: loc.start_offset, length: loc.length }, view_access(pin, decision[:keys]))
          end
        end
      end

      def ctx_receiver?(receiver)
        (receiver.is_a?(Prism::CallNode) && receiver.name == :ctx && receiver.receiver.nil?) ||
          (receiver.is_a?(Prism::LocalVariableReadNode) && receiver.name == :ctx)
      end

      # Precedence:
      #   1. Explicit override (non-empty override_key).
      #   2. Tombstone ("" override_key).
      #   3. Candidate producers (self if it writes the pin, then upstream
      #      writers), latest first. One candidate → its effective key;
      #      several → dominating latest key, else a selection of keys.
      def resolve_pin(pin, input_map)
        if input_map.key?(pin)
          override = input_map[pin]
          return :tombstone if override == TOMBSTONE
          return { kind: :key, key: override }
        end

        candidates = pin_candidates(pin)
        return :none if candidates.empty?

        if candidates.size == 1
          key = effective_key(candidates.first, pin)
          return :none unless key
          return { kind: :key, key: key }
        end

        latest = candidates.first
        if latest != @element_id && dominates?(latest)
          key = effective_key(latest, pin)
          return :none unless key
          return { kind: :key, key: key }
        end

        keys = candidates.map { |id| effective_key(id, pin) }.compact.uniq
        return :none if keys.empty?
        return { kind: :key, key: keys.first } if keys.size == 1

        { kind: :selection, keys: keys }
      end

      def pin_candidates(pin)
        ids = []
        ids << @element_id if Array(@producer_outputs[@element_id]).include?(pin)
        Array(@reachability[@element_id]).each do |pid|
          ids << pid.to_s if Array(@producer_outputs[pid]).include?(pin)
        end
        ids.uniq.sort_by { |id| [-topo_rank(id), id] }
      end

      def topo_rank(id)
        @topo_index[id] || @topo_index[id.to_s] || -1
      end

      def dominates?(candidate)
        set = @dominators[@element_id] || @dominators[@element_id.to_s]
        return false unless set

        set.include?(candidate) || set.include?(candidate.to_s)
      end

      def effective_key(element_id, pin)
        if element_id == @element_id && @output_map&.key?(pin)
          key = @output_map[pin]
          return key if EmissionRewriter.safe_target?(key)
        end
        renamed = @rename_map.dig(element_id, pin) || @rename_map.dig(element_id.to_s, pin)
        if renamed && renamed != pin && EmissionRewriter.safe_target?(renamed)
          return renamed
        end
        return pin if EmissionRewriter.safe_target?(pin)

        nil
      end

      def ctx_access(key)
        "ctx[:#{key}]"
      end

      def latest_access(keys)
        args = keys.map { |k| k.to_sym.inspect }.join(", ")
        "FlowchartRuntime::Outputs.latest(ctx, #{args})"
      end

      def view_access(pin, keys)
        args = ([pin] + keys).map { |k| k.to_sym.inspect }.join(", ")
        "FlowchartRuntime::Outputs.view(ctx, #{args})"
      end
    end
  end
end
