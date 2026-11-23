# frozen_string_literal: true

require "prism"

module FlowchartRuntime
  class LoopState
    # A Ruby indexed assignment target that updates the producer snapshot and
    # its loop slot together. Ruby itself supplies +=, ||=, &&= and parallel
    # assignment semantics, including short-circuiting and single RHS evaluation.
    # No post-step copying: a guarded/conditional write must publish only when
    # the assignment actually executes.
    class Slot
      def initialize(ctx, snapshot, state, read, publication = nil)
        @ctx, @snapshot, @state, @read, @publication = ctx, snapshot, state, read, publication
      end

      def [](_key)
        ExecutedOutputs.read(@ctx, @read).last
      end

      def []=(_key, value)
        LoopState.write(@ctx, @snapshot, value, slot: @state, producer: @publication && @publication[:producer],
          execution: (@publication && @publication[:execution]) || "_loop_io")
      end
    end

    def self.write(ctx, pin, value, slot: nil, producer: nil, execution: "_loop_io")
      key = pin.to_sym
      ctx[key] = value
      ctx[slot.to_sym] = value if slot
      ExecutedOutputs.publish(ctx, { execution: execution, producer: producer }, true, value) if producer
      value
    end

    # Prism provides byte-exact locations, including when ctx is a local
    # variable after a nested activity returns a new context. Simple `=`
    # writes and `[]` reads use the terse helpers; operator writes keep Slot
    # as an lvalue. Implied Entries.scope(ctx) reads are a bare `ctx`
    # argument, not ctx[:pin], so they are never spliced.
    def self.rewrite(body, bindings, reads: {})
      with_reads = rewrite_reads(body, reads)
      rewrite_writes(with_reads, bindings)
    end

    def self.rewrite_reads(body, reads)
      return body if reads.respond_to?(:empty?) && reads.empty?

      edits = []
      queue = [Prism.parse(body).value]
      while (node = queue.pop)
        queue.concat(node.compact_child_nodes)
        next unless node.respond_to?(:receiver) && node.respond_to?(:arguments) && ctx_receiver?(node.receiver)
        next unless node.is_a?(Prism::CallNode) && %i[[] dig fetch key? has_key? include? member?].include?(node.name)

        key = node.arguments&.arguments&.first
        next unless key.is_a?(Prism::SymbolNode)
        target = reads[key.unescaped]
        next unless target

        if target.is_a?(Hash) && node.name == :[]
          edits << [node.location.start_offset, node.location.length, fetch_call(target)]
        elsif target.is_a?(Hash)
          location = node.receiver.location
          edits << [location.start_offset, location.length, "FlowchartRuntime::ExecutedOutputs.read_context(ctx, #{target.inspect})"]
        else
          edits << [key.location.start_offset, key.location.length, target.to_sym.inspect]
        end
      end
      apply_edits(body, edits)
    end
    private_class_method :rewrite_reads

    def self.rewrite_writes(body, bindings)
      return body if bindings.empty?

      edits = []
      queue = [Prism.parse(body).value]
      while (node = queue.pop)
        queue.concat(node.compact_child_nodes)
        next unless node.respond_to?(:receiver) && node.respond_to?(:arguments) && ctx_receiver?(node.receiver)
        next unless write_node?(node) && node.closing_loc

        key = node.arguments&.arguments&.first
        next unless key.is_a?(Prism::SymbolNode)
        binding = bindings[key.unescaped]
        next unless binding && (binding[:state] || binding[:publication])

        if simple_assign?(node)
          rhs = node.arguments.arguments[1]
          next unless rhs

          replacement = write_call(binding, body.byteslice(rhs.location.start_offset, rhs.location.length))
          edits << [node.location.start_offset, node.location.length, replacement]
        else
          start = node.receiver.location.start_offset
          length = node.closing_loc.end_offset - start
          args = binding.values_at(:snapshot, :state, :read, :publication).map { |value| value.is_a?(String) ? value.to_sym.inspect : value.inspect }.join(", ")
          edits << [start, length, "FlowchartRuntime::LoopState::Slot.new(ctx, #{args})[:value]"]
        end
      end
      apply_edits(body, edits)
    end
    private_class_method :rewrite_writes

    def self.write_call(binding, rhs)
      pin = binding[:snapshot] || binding[:read]
      args = ["ctx", pin.to_s.start_with?(":") ? pin.to_s : ":#{pin}", rhs]
      kwargs = []
      kwargs << "slot: :#{binding[:state]}" if binding[:state]
      if (publication = binding[:publication])
        kwargs << "producer: #{publication[:producer].inspect}"
        execution = publication[:execution].to_s
        kwargs << "execution: #{execution.inspect}" unless execution == "_loop_io"
      end
      "FlowchartRuntime::LoopState.write(#{(args + kwargs).join(", ")})"
    end
    private_class_method :write_call

    def self.fetch_call(source)
      args = ["ctx", ":#{source[:pin]}", "candidates: #{Array(source[:candidates]).inspect}"]
      execution = source[:execution].to_s
      args << "execution: #{execution.inspect}" unless execution == "_loop_io"
      "FlowchartRuntime::ExecutedOutputs.fetch(#{args.join(", ")})"
    end
    private_class_method :fetch_call

    def self.apply_edits(body, edits)
      result = body.b.dup
      edits.sort_by(&:first).reverse_each { |start, length, replacement| result[start, length] = replacement.b }
      result.force_encoding(body.encoding)
    end
    private_class_method :apply_edits

    def self.simple_assign?(node)
      node.is_a?(Prism::CallNode) && node.name == :[]=
    end
    private_class_method :simple_assign?

    def self.ctx_receiver?(receiver)
      (receiver.is_a?(Prism::CallNode) && receiver.name == :ctx && receiver.receiver.nil?) ||
        (receiver.is_a?(Prism::LocalVariableReadNode) && receiver.name == :ctx)
    end
    private_class_method :ctx_receiver?

    def self.write_node?(node)
      (node.is_a?(Prism::CallNode) && node.name == :[]=) ||
        [Prism::IndexOperatorWriteNode, Prism::IndexOrWriteNode, Prism::IndexAndWriteNode, Prism::IndexTargetNode].any? { |type| node.is_a?(type) }
    end
    private_class_method :write_node?
  end
end
