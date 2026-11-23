# frozen_string_literal: true

module CodeGenerators
  # Catalog-wide lint for ported step-action bodies (Phase 3 B2).
  class BodyLint
    MAX_LINES = 12
    STANDARD_WRITES = %w[
      model contract errors error_details submission_outcome current_user
    ].freeze

    FALLIBLE = [
      /\.save\b/,
      /\.destroy\b/,
      /\.update\b/,
      /\.deliver\w*/,
      /FlowchartRuntime::Http\.request/,
      /FlowchartRuntime::Entries\.(save|upsert|destroy)/,
      /\bEntries\.(save|upsert|destroy)/,
      /Gateway\.send\b/
    ].freeze

    FORBIDDEN = {
      last_error: /ctx\[:_last_error\]/,
      result_key: /ctx\[:result\]/,
      timeout: /Timeout\.timeout/,
      sleep: /\bsleep\b/,
      rescue_e: /rescue\s*=>\s*\w+/,
      rescue_standard_error: /rescue\s+StandardError/,
      rescue_exception: /rescue\s+Exception/,
      i18n: /I18n\.t\b/
    }.freeze

    Result = Data.define(:ok?, :violations)

    def self.check(body, outputs: [], standard_keys: STANDARD_WRITES)
      new(body, outputs: outputs, standard_keys: standard_keys).check
    end

    def initialize(body, outputs: [], standard_keys: STANDARD_WRITES)
      @body = body.to_s
      @outputs = Array(outputs).map(&:to_s)
      @standard_keys = Array(standard_keys).map(&:to_s)
    end

    def check
      violations = []
      nonempty = significant_lines
      violations << :too_long if nonempty.size > MAX_LINES

      FORBIDDEN.each do |code, pattern|
        violations << code if @body.match?(pattern)
      end
      violations << :bare_local if bare_local?

      if nonempty.last == "true" && fallible_before_last?(nonempty)
        violations << :unchecked_fallible
      end

      allowed = @outputs + @standard_keys
      assigned_keys.each do |key|
        violations << :undeclared_output unless allowed.include?(key)
      end

      Result.new(violations.empty?, violations.uniq)
    end

    private

    def significant_lines
      @body.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    end

    def fallible_before_last?(lines)
      lines[0...-1].any? { |line| FALLIBLE.any? { |pattern| line.match?(pattern) } }
    end

    def assigned_keys
      @body.scan(/ctx\[:(\w+)\]\s*=/).flatten
    end

    BARE_NAMES = %i[params model].freeze

    def bare_local?
      result = Prism.parse("def __lint(ctx, **)\n#{@body}\nend")
      return @body.match?(/(?<![.:\w])(?:params|model)\b(?!:)/) unless result.success?

      receiverless_reference?(result.value)
    end

    def receiverless_reference?(node)
      case node
      when Prism::CallNode
        return true if node.receiver.nil? && BARE_NAMES.include?(node.name) && node.arguments.nil? && node.block.nil?
      when Prism::LocalVariableReadNode
        return true if BARE_NAMES.include?(node.name)
      end
      node.compact_child_nodes.any? { |child| receiverless_reference?(child) }
    end
  end
end
