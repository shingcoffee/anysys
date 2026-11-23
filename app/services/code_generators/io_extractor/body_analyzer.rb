# frozen_string_literal: true

require "ripper"

module CodeGenerators
  module IoExtractor
    # BodyAnalyzer walks a Ruby source string and returns the literal
    # `ctx[:symbol]` occurrences classified as reads and/or writes, each with
    # byte-offset positions into the source. This is the foundational
    # primitive used by IoExtractor and EmissionRewriter.
    #
    # Rules:
    # * Only literal `ctx[:symbol]` (single symbol argument) is considered.
    # * Dynamic access (`ctx[var]`, `ctx[expr.to_sym]`) is skipped.
    # * `ctx[:x] = ...`        -> write
    # * `ctx[:x] ||= ...`      -> read AND write at same span
    # * `ctx[:x]` elsewhere    -> read
    # * In `ctx[:x][:y]` only the outer `ctx[:x]` is recorded.
    # * Occurrences inside comments are ignored (sexp never reports them).
    # * `ctx[:x]` inside string interpolation is still a read.
    # * `FlowchartRuntime::Entries.scope(ctx)` is a read of `bound_entity`
    #   and `customer_id` (the helper indexes those keys on ctx). These reads
    #   are tagged `implied: true`: their span is the bare `ctx` argument, so
    #   rewriters must never splice over it.
    # * Unparseable or empty source -> `{reads: [], writes: []}`.
    #
    # @example
    #   BodyAnalyzer.call("x = ctx[:user]")
    #   # => { reads: [{pin: "user", start: 4, length: 10}], writes: [] }
    class BodyAnalyzer
      def self.call(source)
        new(source).call
      end

      def initialize(source)
        @source = source.to_s
      end

      def call
        return { reads: [], writes: [] } if @source.empty?

        sexp = Ripper.sexp(@source)
        return { reads: [], writes: [] } if sexp.nil?

        occurrences = []
        walk(sexp, context: :read, sink: occurrences)

        reads  = []
        writes = []
        occurrences.each do |occ|
          start_offset = byte_offset(occ[:line], occ[:col])
          next if start_offset.nil?

          length = occ[:length] || ctx_span_length(occ[:pin])
          entry  = { pin: occ[:pin], start: start_offset, length: length }
          entry[:implied] = true if occ[:implied]

          reads  << entry if occ[:kind] == :read  || occ[:kind] == :both
          writes << entry if occ[:kind] == :write || occ[:kind] == :both
        end

        reads.sort_by!  { |r| r[:start] }
        writes.sort_by! { |w| w[:start] }

        { reads: reads, writes: writes }
      end

      private

      # Recursively walks the sexp tree. `context` is either :read (default
      # expression position) or a write context propagated from an enclosing
      # :assign / :opassign so that `aref_field` children know whether to be
      # classified as pure write or both read+write.
      def walk(node, context:, sink:)
        return unless node.is_a?(Array)

        case node.first
        when :assign
          # [:assign, lhs, rhs]
          walk(node[1], context: :write,    sink: sink)
          walk(node[2], context: :read,     sink: sink)
          return
        when :opassign
          # [:opassign, lhs, op, rhs]
          walk(node[1], context: :opwrite,  sink: sink)
          walk(node[3], context: :read,     sink: sink)
          return
        when :massign
          # [:massign, lhs_list, rhs] — each LHS element is a write.
          walk(node[1], context: :write,    sink: sink)
          walk(node[2], context: :read,     sink: sink)
          return
        when :aref
          # Read position — record if it's ctx[:sym].
          record_if_ctx_literal(node, kind: :read, sink: sink)
          # Recurse into children: the receiver may itself be ctx[:x] (chained
          # access), and the index arguments could contain nested exprs.
          walk(node[1], context: :read, sink: sink)
          walk(node[2], context: :read, sink: sink)
          return
        when :aref_field
          # Write-or-both position.
          kind = context == :opwrite ? :both : :write
          record_if_ctx_literal(node, kind: kind, sink: sink)
          # Receiver is the thing being indexed (e.g. `ctx` or a chained
          # ctx[:x] aref). Recurse into it as a READ — in `ctx[:x][:y] = 1`
          # the inner aref on ctx is a read.
          walk(node[1], context: :read, sink: sink)
          walk(node[2], context: :read, sink: sink)
          return
        when :method_add_arg
          record_entries_scope_reads(node, sink: sink)
        end

        node.each { |child| walk(child, context: :read, sink: sink) if child.is_a?(Array) }
      end

      # Matches exactly `ctx[:literal_symbol]` and captures pin + ctx position.
      def record_if_ctx_literal(aref_node, kind:, sink:)
        receiver = aref_node[1]
        args     = aref_node[2]

        return unless vcall_ctx?(receiver)

        pin_info = extract_single_symbol_pin(args)
        return if pin_info.nil?

        ctx_pos = receiver[1][2] # [:vcall, [:@ident, "ctx", [line, col]]]
        sink << {
          pin:  pin_info,
          kind: kind,
          line: ctx_pos[0],
          col:  ctx_pos[1]
        }
      end

      def vcall_ctx?(node)
        node.is_a?(Array) &&
          node[0] == :vcall &&
          node[1].is_a?(Array) &&
          node[1][0] == :@ident &&
          node[1][1] == "ctx"
      end

      # Entries.scope(ctx) reads ctx[:bound_entity] and ctx[:customer_id]
      # inside the helper; those pins must show up as step inputs even
      # though the emitted source never writes `ctx[:bound_entity]`.
      def record_entries_scope_reads(node, sink:)
        call = node[1]
        return unless call.is_a?(Array) && call[0] == :call
        return unless call[3].is_a?(Array) && call[3][0] == :@ident && call[3][1] == "scope"
        return unless entries_const_path?(call[1])

        ctx_pos = sole_ctx_arg_position(node[2])
        return unless ctx_pos

        %w[bound_entity customer_id].each do |pin|
          sink << { pin: pin, kind: :read, line: ctx_pos[0], col: ctx_pos[1], length: 3, implied: true }
        end
      end

      def entries_const_path?(node)
        node.is_a?(Array) &&
          node[0] == :const_path_ref &&
          node[1].is_a?(Array) && node[1][0] == :var_ref &&
          node[1][1].is_a?(Array) && node[1][1][0] == :@const && node[1][1][1] == "FlowchartRuntime" &&
          node[2].is_a?(Array) && node[2][0] == :@const && node[2][1] == "Entries"
      end

      def sole_ctx_arg_position(args)
        list = args
        list = args[1] if args.is_a?(Array) && args[0] == :arg_paren
        return nil unless list.is_a?(Array) && list[0] == :args_add_block

        arg_list = list[1]
        return nil unless arg_list.is_a?(Array) && arg_list.length == 1

        arg = arg_list[0]
        return nil unless vcall_ctx?(arg)

        arg[1][2]
      end

      # Returns the pin name (String) when args is exactly one symbol literal
      # with an identifier body; nil otherwise (covers dynamic / composite
      # arguments).
      def extract_single_symbol_pin(args)
        return nil unless args.is_a?(Array) && args[0] == :args_add_block

        arg_list = args[1]
        return nil unless arg_list.is_a?(Array) && arg_list.length == 1

        sym = arg_list[0]
        return nil unless sym.is_a?(Array) && sym[0] == :symbol_literal

        inner = sym[1]
        return nil unless inner.is_a?(Array) && inner[0] == :symbol

        ident = inner[1]
        return nil unless ident.is_a?(Array) && %i[@ident @const @kw].include?(ident[0])

        ident[1]
      end

      # Converts Ripper's (line, col) position to a byte offset into @source.
      # MRI Ripper columns are *byte* offsets from the start of the line (the
      # same unit Prism `start_offset` uses). Adding them to a byte-indexed
      # line start is enough — treating `col` as a character index and
      # measuring `line_string[0, col].bytesize` double-counts CJK prefixes
      # and lands the span at EOF.
      def byte_offset(line, col)
        return nil if line < 1

        line_start = line_byte_offsets[line - 1]
        return nil if line_start.nil?

        line_start + col
      end

      def line_byte_offsets
        @line_byte_offsets ||= begin
          bytes   = @source.b
          offsets = [0]
          pos     = 0
          while (nl = bytes.index("\n".b, pos))
            offsets << nl + 1
            pos = nl + 1
          end
          offsets
        end
      end

      def ctx_span_length(pin)
        # `ctx[:` + pin + `]`
        5 + pin.bytesize + 1
      end
    end
  end
end
