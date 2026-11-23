# frozen_string_literal: true

require "prism"

module CodeGenerators
  # Re-wraps over-long lines of generated Ruby. Only the elements of a
  # parenthesised argument list, an array literal or a hash literal are moved
  # onto their own lines; every token is kept, so the program is unchanged.
  #
  #   ctx[:total] = FlowchartRuntime::Pricing.calculate(ctx, lines: ctx[:items], tax_rate: 0.1, …)
  #
  # becomes
  #
  #   ctx[:total] = FlowchartRuntime::Pricing.calculate(
  #     ctx,
  #     lines: ctx[:items],
  #     tax_rate: 0.1,
  #     …
  #   )
  class SourceFormatter
    MAX_WIDTH = 100
    INDENT = "  "
    # A step method is written one level inside its activity class.
    STEP_WIDTH = MAX_WIDTH - INDENT.length
    MAX_PASSES = 500

    # What may follow a wrapped list on its line: a method chain, closing
    # delimiters and commas, then optionally a block opener.
    LINE_TAIL = /\A(?:\.[a-z_]\w*[?!]?)*[,)\]}]*(?: (?:do|\{)(?: \|[^|]*\|)?)?\s*\z/

    STRING_NODES = [
      Prism::InterpolatedStringNode, Prism::InterpolatedSymbolNode,
      Prism::InterpolatedRegularExpressionNode, Prism::InterpolatedXStringNode
    ].freeze

    def self.call(source, max_width: MAX_WIDTH)
      new(source, max_width).call
    end

    def initialize(source, max_width)
      @source = source.to_s
      @max_width = max_width
    end

    def call
      source = @source
      MAX_PASSES.times do
        result = Prism.parse(source)
        return source unless result.success?

        target = widest_breakable(source, result.value)
        return source unless target

        source = wrap(source, *target)
      end
      source
    end

    private

    # The breakable node on the first over-long line that has one. Prefer the
    # widest so the outermost call is wrapped before the literals inside it.
    def widest_breakable(source, root)
      long_lines = source.lines.each_with_index.filter_map do |line, index|
        index + 1 if line.chomp.length > @max_width
      end
      return if long_lines.empty?

      candidates = breakables(root, source).group_by { |_node, (_elements, opening, _closing)| opening.start_line }
      long_lines.each do |line|
        best = Array(candidates[line]).max_by { |node, (_elements, _opening, closing)| closing.end_offset - node.location.start_offset }
        return best if best
      end
      nil
    end

    def breakables(node, source, found = [], inline: false)
      return found if STRING_NODES.any? { |klass| node.is_a?(klass) }

      elements = breakable_elements(node, source) unless inline
      found << [node, elements] if elements
      inline ||= inline_context?(node)
      node.compact_child_nodes.each { |child| breakables(child, source, found, inline: inline) }
      found
    end

    # Operands of operators, `&&`/`||`, ternaries and modifier conditionals stay
    # on one line: splitting them leaves the rest of the expression dangling.
    def inline_context?(node)
      case node
      when Prism::AndNode, Prism::OrNode, Prism::RescueModifierNode then true
      when Prism::IfNode, Prism::UnlessNode then node.end_keyword_loc.nil?
      when Prism::WhileNode, Prism::UntilNode then node.closing_loc.nil?
      when Prism::CallNode then operator_call?(node)
      else false
      end
    end

    def operator_call?(node)
      node.receiver && node.call_operator_loc.nil? && node.opening_loc.nil? && !%i[[] []=].include?(node.name)
    end

    # A trailing `do … end` block may span lines; the delimited list itself
    # must still be on one line and close the line, so an operand in the
    # middle of an expression or modifier is never split.
    def breakable_elements(node, source)
      elements, opening, closing = parts(node)
      return unless opening && closing && elements.size > 1
      return unless node.location.start_line == opening.start_line && opening.start_line == closing.start_line
      return unless line_tail(source, closing).match?(LINE_TAIL)
      return if elements.any? { |element| heredoc?(element) }

      [elements, opening, closing]
    end

    def line_tail(source, closing)
      bytes = source.b
      line_end = bytes.index("\n", closing.end_offset) || bytes.bytesize
      bytes.byteslice(closing.end_offset, line_end - closing.end_offset).force_encoding(source.encoding)
    end

    def parts(node)
      case node
      when Prism::CallNode
        return [] unless node.opening_loc&.slice == "("

        arguments = Array(node.arguments&.arguments).flat_map do |argument|
          argument.is_a?(Prism::KeywordHashNode) ? argument.elements : [argument]
        end
        arguments << node.block if node.block.is_a?(Prism::BlockArgumentNode)
        [arguments, node.opening_loc, node.closing_loc]
      when Prism::ArrayNode
        return [] unless node.opening_loc&.slice == "["

        [node.elements, node.opening_loc, node.closing_loc]
      when Prism::HashNode
        [node.elements, node.opening_loc, node.closing_loc]
      else
        []
      end
    end

    def heredoc?(node)
      return true if node.respond_to?(:opening_loc) && node.opening_loc&.slice&.start_with?("<<")

      node.compact_child_nodes.any? { |child| heredoc?(child) }
    end

    def wrap(source, _node, (elements, opening, closing))
      bytes = source.b
      line_start = bytes.rindex("\n", opening.start_offset - 1)&.succ || 0
      indent = bytes[line_start...opening.start_offset][/\A */]
      inner = indent + INDENT

      lines = elements.map { |element| inner + bytes.byteslice(element.location.start_offset, element.location.length) }
      replacement = "\n#{lines.join(",\n")}\n#{indent}"

      result = bytes.dup
      result[opening.end_offset...closing.start_offset] = replacement.b
      result.force_encoding(source.encoding)
    end
  end
end
