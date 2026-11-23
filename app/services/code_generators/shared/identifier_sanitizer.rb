# frozen_string_literal: true

module CodeGenerators
  module Shared
    # Shared helpers for safely emitting user-supplied strings into generated
    # Ruby source. Every method in this module is defensive — when input
    # fails validation the emitter returns a safe fallback (usually `nil` or
    # a comment) rather than producing Ruby that would either fail to parse
    # or silently execute injected code at runtime.
    module IdentifierSanitizer
      # A plain Ruby local / attribute / symbol identifier.
      IDENT_RE = /\A[a-z_][a-zA-Z0-9_]*\z/
      # A plain Ruby constant.
      CONST_RE = /\A[A-Z][a-zA-Z0-9_]*\z/
      # Nested constant path (e.g. Emails::DeliverMessageJob).
      NESTED_CONST_RE = /\A[A-Z][a-zA-Z0-9_]*(::[A-Z][a-zA-Z0-9_]*)*\z/

      RUBY_RESERVED = %w[
        BEGIN END alias and begin break case class def defined? do else
        elsif end ensure false for if in module next nil not or redo
        rescue retry return self super then true undef unless until when
        while yield __FILE__ __LINE__ __ENCODING__
      ].to_set.freeze

      # Is this string usable as a ctx key / local name?
      def safe_ident?(value)
        s = value.to_s
        return false if s.empty?
        return false unless IDENT_RE.match?(s)
        return false if RUBY_RESERVED.include?(s)
        true
      end

      # Return +value+ when it is a safe Ruby identifier, otherwise +default+.
      #
      # This is the value-returning counterpart of #safe_ident?, and the
      # repo-wide generalisation of LoopGenerator#safe_loop_ident. Generators
      # splice ctx variable names straight into emitted source
      # (`ctx[:#{name}]`), so an unvalidated name such as
      # `"x]; Kernel.raise('pwn'); ctx[:y"` would land in code position. Route
      # every such name through this method.
      def safe_ident(value, default:)
        s = value.to_s.strip
        return default if s.empty?
        return default unless IDENT_RE.match?(s)
        return default if RUBY_RESERVED.include?(s)
        s
      end

      # A data key (hash key / column / field name) that is safe to splice as a
      # Ruby symbol literal. Laxer than #safe_ident? — data keys legitimately
      # start with an uppercase letter and may collide with Ruby keywords
      # (`:end` is a perfectly good symbol) — but still refuses anything
      # carrying quotes, brackets, statement separators or newlines.
      KEY_RE = /\A[A-Za-z_][A-Za-z0-9_]*\z/

      def safe_key?(value)
        KEY_RE.match?(value.to_s)
      end

      # `":a, :b"` for the entries of +values+ that are safe data keys. Unsafe
      # entries are dropped rather than spliced into code position.
      def safe_symbols(values, separator: ", ")
        Array(values).map(&:to_s).select { |v| safe_key?(v) }.map { |v| ":#{v}" }.join(separator)
      end

      # Read an identifier-typed config key, validated.
      def ident_config(key, default: nil)
        safe_ident(config[key], default: default)
      end

      # Keys of a key/value list that are usable as Ruby identifiers. Rows with
      # an unusable key are dropped rather than spliced into code position.
      def safe_ident_keys(raw)
        CodeGenerators::Shared::KeyValueList.keys(raw).select { |k| safe_ident?(k) }
      end

      # Emit a Ruby `ctx[:NAME]` read, returning `nil` (source text "nil")
      # when NAME is not a safe identifier. Callers that want to emit the
      # lookup even for non-safe names can use `String#inspect` themselves.
      def safe_ctx_read(name)
        safe_ident?(name) ? "ctx[:#{name}]" : "nil"
      end

      # Emit a Ruby `ctx[:NAME] = VALUE_EXPR` assignment with a safe
      # identifier check. When NAME is unsafe we emit a TODO comment so
      # the generated file is still valid Ruby and the problem is visible.
      def safe_ctx_assign(name, value_expr)
        if safe_ident?(name)
          "ctx[:#{name}] = #{value_expr}"
        else
          "# TODO: skipped assignment to unsafe ctx key #{name.inspect}"
        end
      end

      # Format a value suitable for interpolation into double-quoted Ruby
      # string literals. Uses String#inspect, which escapes any `"`, `\`,
      # `#{...}`, or control characters — preventing injection of extra
      # code or extra header lines (CRLF).
      def safe_string_literal(value)
        value.to_s.inspect
      end

      # Strip control characters (CR/LF/NUL/etc.) out of a string before
      # it is used as an HTTP header key or value. HTTP disallows these
      # characters, but generated code that interpolates raw user input
      # can produce Ruby that either fails to parse (an embedded newline
      # closes the string literal) or produces malformed HTTP requests.
      def strip_control_chars(value)
        value.to_s.gsub(/[\r\n\t\x00-\x1F\x7F]+/, " ")
      end

      # Return a Ruby constant reference for a class-name config value IF
      # it appears on the allowlist; otherwise `nil`. Use this to refuse
      # generating code that evaluates arbitrary constants (e.g.
      # `is_a?(ARBITRARY_CONST)`).
      def safe_constant(name, allowlist:, nested: false)
        s = name.to_s.strip
        pattern = nested ? NESTED_CONST_RE : CONST_RE
        return nil unless pattern.match?(s)
        return nil unless allowlist.include?(s)
        s
      end

      def safe_nested_constant?(name)
        NESTED_CONST_RE.match?(name.to_s.strip)
      end
    end
  end
end
