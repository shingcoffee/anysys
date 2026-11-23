# frozen_string_literal: true

require "ripper"
require "prism"

module CodeGenerators
  module Shared
    # Hardening for the *expression* config fields — the ones a flowchart
    # author fills with a fragment of Ruby that the generator splices into
    # emitted source in code position (collection expressions, custom reducer
    # bodies, computed-field expressions, response bodies, ...).
    #
    # Those fields are an expression **by design**: the feature does not exist
    # without them, so they cannot be quoted with String#inspect the way an
    # identifier or a literal can. What they must not do is *break out of their
    # syntactic context* — an author (or anyone who can reach the flowchart
    # editor) must not be able to turn a one-operand slot into a statement list
    # that runs extra code the surrounding template never intended, nor emit an
    # activity that fails to compile.
    #
    # Trust boundary: an expression field is Ruby authored by a tenant admin and
    # executed inside that tenant's generated Activity. It is equivalent in
    # privilege to hand-writing the Activity, and is NOT reachable by end users
    # or by request data. What this module guarantees is only the weaker (but
    # essential) property that the expression stays *one expression*:
    #
    #   * it must parse on its own, and
    #   * it must be a single top-level statement — no `;`, no newline-separated
    #     second statement, no unbalanced bracket that swallows the template's
    #     own punctuation.
    #
    # That closes the "operand slot becomes a statement list" escape
    # (`1); Kernel.raise("pwn"); (`) while leaving every legitimate expression
    # (`ctx[:items]`, `acc + item[:amount].to_f`, `a.b.c || []`) untouched.
    module ExpressionSafety
      # Ruby source that parses and contains exactly one top-level statement.
      def safe_single_expression?(source)
        text = source.to_s.strip
        return false if text.empty? || !safe_expression?(text)

        result = Prism.parse(text)
        result.success? && result.value.statements.body.size == 1
      end

      # Ruby source that parses and contains exactly one top-level statement.
      def safe_expression?(source)
        s = source.to_s.strip
        return false if s.empty?

        # A `#` comment would let a payload terminate an emitted comment line
        # and make the remainder executable, while still parsing as a single
        # statement on its own. Expression fields never need comments.
        tokens = begin
          Ripper.lex(s)
        rescue StandardError
          nil
        end
        return false if tokens.nil?
        return false if tokens.any? { |(_pos, type, _tok, _state)| type == :on_comment }

        sexp = begin
          Ripper.sexp(s)
        rescue StandardError
          nil
        end
        return false if sexp.nil?

        statements = sexp.dig(1)
        return false unless statements.is_a?(Array)
        statements.compact.size == 1
      end

      # Parenthesised expression source, or +default+ when the value is not a
      # single safe expression. Parenthesising is what makes the guarantee
      # hold at the splice site: a payload that tried to close the template's
      # bracket now has to close ours first, which #safe_expression? rejects.
      def safe_expression(source, default: "nil")
        safe_expression?(source) ? "(#{source.to_s.strip})" : default
      end

      # Same check, but returns the raw source (no added parens) for splice
      # sites that already supply their own delimiters (e.g. a block body).
      def safe_expression_source(source, default: nil)
        safe_expression?(source) ? source.to_s.strip : default
      end

      # Read an expression-typed config key, validated. Returns +default+ when
      # the configured value is not a single safe Ruby expression.
      def expression_config(key, default: nil)
        safe_expression_source(config[key], default: default)
      end

      # Map the values of a key/value list through the expression check,
      # dropping rows whose value is not a single safe expression.
      def safe_expression_pairs(raw)
        CodeGenerators::Shared::KeyValueList.pairs(raw).filter_map do |(k, v)|
          expr = safe_expression_source(v)
          expr.nil? ? nil : [k, expr]
        end
      end

      # `conditions` rows for a `.where(...)` call. The column has already been
      # validated by FlowchartRuntime::ConditionInput (COLUMN_RE); the *value*
      # is Ruby source by design (`"active"`, `true`, `ctx[:id]`), so it goes
      # through the single-expression check and unsafe rows are dropped.
      def safe_where_pairs(raw)
        FlowchartRuntime::ConditionInput.literal_pairs(raw).filter_map do |(column, value)|
          expr = safe_expression_source(value)
          expr.nil? ? nil : [column, expr]
        end
      end

      # A one-line rendering safe to embed in an emitted `#` comment. A raw
      # newline would terminate the comment and make the remainder executable
      # (the escape LoopGenerator's legacy-condition handling was written for).
      def safe_comment_text(value)
        value.to_s.gsub(/[\r\n]+/, " ")
      end
    end
  end
end
