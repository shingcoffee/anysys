# frozen_string_literal: true

require "prism"

module CodeGenerators
  # Reads and replaces the class body of a generator file by source range, so
  # nested blocks, heredocs, comments and declarations survive an edit.
  class SourceDocument
    attr_reader :source, :generator_class

    def initialize(source)
      @source = source
      @generator_class = find_class(Prism.parse(source).value)
    end

    def body
      source.byteslice(body_range)
    end

    def with_body(body)
      body = body.gsub("\r\n", "\n")
      body += "\n" unless body.end_with?("\n")
      result = source.b
      result[body_range] = body.b
      result.force_encoding(source.encoding)
    end

    private

    def find_class(node)
      return node if node.is_a?(Prism::ClassNode) && node.superclass

      node.compact_child_nodes.each do |child|
        found = find_class(child)
        return found if found
      end
      nil
    end

    def body_range
      first = source.b.index("\n", generator_class.superclass.location.end_offset) + 1
      last = generator_class.end_keyword_loc.start_offset - generator_class.end_keyword_loc.start_column
      first...last
    end
  end
end
