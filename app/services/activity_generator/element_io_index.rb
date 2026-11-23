# frozen_string_literal: true

class ActivityGenerator
  # Precomputes the shared I/O state that every element-body rewrite needs:
  #   - rename_map:        element_id -> { pin => renamed_key } (from ConflictResolver)
  #   - reachability:      element_id -> ordered predecessor ids (farthest-first /
  #                        closest-last) so EmissionRewriter can list upstream writers
  #   - producer_outputs:  element_id -> array of original pin names emitted by that element
  #   - dominators:        element_id -> Set of ids that dominate it on the forward
  #                        dataflow graph rooted at Start
  #   - topo_index:        element_id -> index in topological order (latest writer first)
  class ElementIoIndex
    # Keys the runtime writes for its own bookkeeping: every loop header resets
    # the iteration counter and decisions stash route values, so they are never
    # dataflow producers and must not be renamed apart.
    RUNTIME_PIN = /\A_(?:route_\d+|loop_iteration_count)\z/

    # @param elements    [Array<Hash>]
    # @param connections [Array<Hash>]
    # @param topological_order_provider [#call] returns Kahn-ordered array of element ids
    def initialize(elements, connections, topological_order_provider:, loop_topology: nil, scope: nil)
      @elements = elements
      @loop_topology = loop_topology || LoopTopology.new(elements, connections)
      @connections = @loop_topology.dataflow_connections
      @topological_order_provider = topological_order_provider
      @scope = scope
    end

    # @return [Hash] with keys :rename_map, :reachability, :producer_outputs,
    #   :dominators, :topo_index
    def build
      effective_outputs = {}
      @elements.each do |el|
        effective_outputs[el["id"]] = element_effective_output_keys(el)
      end

      descriptors = @elements.map do |el|
        {
          id:      el["id"],
          outputs: effective_outputs[el["id"]].map { |k| { pin: k } }
        }
      end

      topo_order = if @loop_topology.regions.empty?
        @topological_order_provider.call
      else
        GraphBuilder.new(@elements, @connections).topological_order
      end
      reachability = build_element_reachability
      ancestors = reachability.transform_values { |ids| ids.to_set }
      rename_map = overlay_author_renames(
        CodeGenerators::ConflictResolver.call(
          descriptors, topo_order: topo_order, ancestors: ancestors
        )
      )

      # producer_outputs maps element_id -> array of ORIGINAL pin names (before rename).
      # EmissionRewriter.resolve_read looks up original pin names to find which
      # producer emits a given key, then follows rename_map to get the effective key.
      producer_outputs = {}
      effective_outputs.each do |id, keys|
        producer_outputs[id] = keys
      end

      loop_plan = LoopIoPlan.new(elements: @elements, topology: @loop_topology,
        outputs: producer_outputs, scope: @scope).build
      {
        rename_map: rename_map,
        reachability: reachability,
        producer_outputs: producer_outputs,
        dominators: build_dominators,
        topo_index: topo_order.each_with_index.to_h
      }.merge(loop_plan)
    end

    # Merge conflict-resolver renames into an element's io_overrides.
    # An author-supplied override for the same pin wins (explicit over implicit).
    # @param element    [Hash]
    # @param io_index   [Hash] the result of #build (must be pre-computed)
    # @return [Hash] overrides hash with "inputs" and "outputs" keys
    def self.merge_rename_map_into_overrides(element, io_index)
      raw = element.dig("properties", "io_overrides") || {}
      overrides = {
        "inputs"  => Array(raw["inputs"]  || raw[:inputs]).dup,
        "outputs" => Array(raw["outputs"] || raw[:outputs]).dup
      }

      pin_rewrites = io_index[:rename_map][element["id"]] || {}
      existing_pins = overrides["outputs"].filter_map { |o| safe_author_output_pin(o) }.to_set
      pin_rewrites.each do |pin, renamed|
        next if existing_pins.include?(pin.to_s)
        overrides["outputs"] << { "pin" => pin.to_s, "renamed_to" => renamed.to_s }
      end
      overrides
    end

    def self.safe_author_output_pin(entry)
      pin = (entry["pin"] || entry[:pin]).to_s
      renamed = (entry["renamed_to"] || entry[:renamed_to]).to_s
      return if pin.empty? || renamed.empty? || renamed == pin
      return unless CodeGenerators::EmissionRewriter.safe_target?(renamed)

      pin
    end

    private

    # Author-persisted outputs.renamed_to wins over the conflict-resolver
    # suffix so every reader resolves the key that is actually written.
    def overlay_author_renames(rename_map)
      @elements.each do |el|
        raw = el.dig("properties", "io_overrides") || {}
        Array(raw["outputs"] || raw[:outputs]).each do |entry|
          pin = self.class.safe_author_output_pin(entry)
          next unless pin

          renamed = (entry["renamed_to"] || entry[:renamed_to]).to_s
          rename_map[el["id"]] ||= {}
          rename_map[el["id"]][pin] = renamed
        end
      end
      rename_map
    end

    def element_effective_output_keys(element)
      type = element["type"]
      if type == "process"
        step_effective_keys(element).values.flatten.uniq
      else
        result = CodeGenerators::IoExtractor.call_element(
          element_type: type,
          properties:   element["properties"] || {}
        )
        (result[:outputs] || []).map { |o| (o[:pin] || o["pin"]).to_s }.grep_v(RUNTIME_PIN)
      end
    end

    def step_effective_keys(process_el)
      out = {}
      steps = process_el.dig("properties", "steps") || []
      steps.each_with_index do |step, index|
        action = step["action"]
        next if action.blank?

        pins = CodeGenerators::IoExtractor.call(
          action: action,
          config: step["config"] || {}
        )
        out[index] = (pins[:outputs] || []).map { |o| o[:pin] }
      end
      out
    end

    def build_dominators
      start_id = @elements.find { |el| el["type"] == "start" }&.dig("id")
      return {} unless start_id

      adj = Hash.new { |h, k| h[k] = [] }
      @connections.each { |c| adj[c["from"]] << c["to"] }

      nodes = reachable_from(start_id, adj)
      preds = Hash.new { |h, k| h[k] = [] }
      adj.each do |from, tos|
        next unless nodes.include?(from)
        tos.each { |to| preds[to] << from if nodes.include?(to) }
      end

      all = nodes.dup
      dom = {}
      nodes.each { |n| dom[n] = n == start_id ? Set[start_id] : all.dup }

      changed = true
      while changed
        changed = false
        nodes.each do |n|
          next if n == start_id
          incoming = preds[n]
          next if incoming.empty?

          inter = incoming.map { |p| dom[p] }.reduce(:&)
          new_dom = inter | Set[n]
          if new_dom != dom[n]
            dom[n] = new_dom
            changed = true
          end
        end
      end
      dom
    end

    def reachable_from(start_id, adj)
      seen = Set.new
      queue = [start_id]
      while (id = queue.shift)
        next unless seen.add?(id)
        queue.concat(adj[id])
      end
      seen
    end

    def build_element_reachability
      adj = Hash.new { |h, k| h[k] = [] }
      @connections.each { |c| adj[c["from"]] << c["to"] }

      reverse_adj = Hash.new { |h, k| h[k] = [] }
      adj.each { |from, tos| tos.each { |to| reverse_adj[to] << from } }

      result = {}
      @elements.each do |el|
        result[el["id"]] = ordered_predecessors(el["id"], reverse_adj)
      end
      result
    end

    # BFS walks predecessors layer-by-layer from the target outward. Each layer
    # is prepended via unshift, so once the walk finishes the accumulated order
    # is farthest-first / closest-last. ConflictResolver uses the set of these
    # ids as ancestors; EmissionRewriter still receives the ordered list.
    def ordered_predecessors(target_id, reverse_adj)
      visited = Set.new([target_id])
      order   = []
      queue   = [target_id]
      while (cur = queue.shift)
        reverse_adj[cur].each do |pred|
          next if visited.include?(pred)
          visited << pred
          order.unshift(pred)
          queue << pred
        end
      end
      order
    end
  end
end
