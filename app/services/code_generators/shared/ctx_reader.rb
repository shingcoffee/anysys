# frozen_string_literal: true

module CodeGenerators
  module Shared
    module CtxReader
      IDENT_SEGMENT_RE = /\A[a-zA-Z_][a-zA-Z0-9_]*\z/

      def safe_read(ctx_var, type: :any)
        name = ctx_var.to_s
        # A dotted path (`user.items`) or any non-identifier collapses into a
        # chain of dig calls; otherwise emit the bare `ctx[:NAME]` form so
        # existing output stays unchanged. Prior behaviour produced invalid
        # Ruby (e.g. `ctx[:user.items]`) for any dotted source.
        #
        # Each path segment MUST be a valid Ruby identifier. Without this
        # guard a name like `"items]; system('id'); ctx[:foo"` would be
        # spliced verbatim into the lookup and execute at runtime. Nested
        # segments go through Step.dig, which also reads records.
        lookup =
          if name.match?(/\A[a-z_][a-zA-Z0-9_]*\z/)
            "ctx[:#{name}]"
          else
            parts = name.split(".").map(&:strip).reject(&:empty?)
            return "nil" if parts.empty?
            return "nil" if parts.any? { |p| !p.match?(IDENT_SEGMENT_RE) }

            root, *rest = parts
            next_keys = rest.map { |p| ":#{p}" }.join(", ")
            rest.empty? ? "ctx[:#{root}]" : "FlowchartRuntime::Step.dig(ctx[:#{root}], #{next_keys})"
          end

        case type
        when :array  then "(#{lookup} || [])"
        when :hash   then "(#{lookup} || {})"
        when :string then "#{lookup}.to_s"
        else              lookup
        end
      end

      def ensure_array_expr(expr)
        "Array(#{expr})"
      end

      def ensure_hash_expr(expr)
        "((#{expr}).is_a?(Hash) ? #{expr} : {})"
      end
    end
  end
end
