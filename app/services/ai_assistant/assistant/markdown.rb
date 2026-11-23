# frozen_string_literal: true

require "cgi"

module AiAssistant
  module Assistant
    # Narrow markdown for assistant bubbles. Escape first, then add a small
    # set of tags, then sanitize so a model reply cannot inject HTML.
    class Markdown
      TAGS = %w[p br strong em code pre ul ol li a].freeze
      ATTRIBUTES = %w[href].freeze
      FENCE = /```([\s\S]*?)```/
      HEADING = /\A\#{1,6} /
      LIST_ITEMS = { ul: /\A[-*] /, ol: /\A\d+\. / }.freeze

      def self.render(text)
        html = new(text.to_s).to_html
        Rails::HTML::SafeListSanitizer.new.sanitize(html, tags: TAGS, attributes: ATTRIBUTES)
      end

      # A reply's prose followed by the facts the platform appends to it
      # (what was created, what was skipped), the facts as a bulleted list.
      # A lone fact with no prose stays a plain sentence.
      def self.compose(prose, notes = [])
        notes = Array(notes).map { |note| note.to_s.squish }.reject(&:blank?)
        return paragraphs(prose) if notes.empty?
        return notes.first if prose.blank? && notes.one?

        paragraphs(prose, notes.map { |note| "- #{note}" }.join("\n"))
      end

      def self.paragraphs(*parts)
        parts.flatten.map { |part| part.to_s.strip }.reject(&:blank?).join("\n\n")
      end

      def initialize(text)
        @text = text.to_s
      end

      def to_html
        fences = []
        working = @text.gsub(FENCE) do
          fences << Regexp.last_match(1).to_s
          "\n\n@@FENCE#{fences.length - 1}@@\n\n"
        end

        html = blocks(inline(CGI.escapeHTML(working)))
        fences.each_with_index do |code, index|
          html = html.gsub("@@FENCE#{index}@@", "<pre><code>#{CGI.escapeHTML(code.strip)}</code></pre>")
        end
        html
      end

      private

      def inline(text)
        text = text.gsub(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/, '<a href="\2">\1</a>')
        text = text.gsub(/`([^`]+)`/, '<code>\1</code>')
        text = text.gsub(/\*\*([^*]+)\*\*/, '<strong>\1</strong>')
        text.gsub(/(?<!\*)\*([^*]+)\*(?!\*)/, '<em>\1</em>')
      end

      def blocks(text)
        text.split(/\n{2,}/).map { |chunk| render_chunk(chunk.strip) }.reject(&:blank?).join
      end

      def render_chunk(chunk)
        return "" if chunk.blank?
        return chunk if chunk.start_with?("@@FENCE")

        chunk.split("\n")
             .chunk_while { |line, following| line_kind(line) == line_kind(following) }
             .map { |lines| render_lines(line_kind(lines.first), lines) }
             .join
      end

      def line_kind(line)
        return :heading if line.match?(HEADING)

        LIST_ITEMS.find { |_kind, pattern| line.match?(pattern) }&.first || :paragraph
      end

      def render_lines(kind, lines)
        case kind
        when :heading
          lines.map { |line| "<p><strong>#{line.sub(HEADING, "")}</strong></p>" }.join
        when :paragraph
          "<p>#{lines.join("<br>")}</p>"
        else
          items = lines.map { |line| "<li>#{line.sub(LIST_ITEMS.fetch(kind), "")}</li>" }.join
          "<#{kind}>#{items}</#{kind}>"
        end
      end
    end
  end
end
