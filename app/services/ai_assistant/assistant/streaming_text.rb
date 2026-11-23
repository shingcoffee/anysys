# frozen_string_literal: true

module AiAssistant
  module Assistant
    # Turns a half-finished model response into the prose a reader should see.
    #
    # The assistant's wire format is a single JSON object (see
    # AiAssistant::Assistant::ReplyEnvelope), so streaming raw tokens would
    # show `{"intent":"chat","reply":"Su` — worse than no streaming at all.
    # This pulls the in-progress value of the `reply` key out of a document
    # that is still arriving, decoding escapes as far as they are complete and
    # stopping cleanly on a truncated one.
    #
    # It is deliberately tolerant rather than correct-or-nothing: it is only
    # ever used for the live preview, and the authoritative parse still runs on
    # the finished document.
    module StreamingText
      REPLY_KEY = /"reply"\s*:\s*"/
      FENCE = /\A```(?:json)?[ \t]*\r?\n?/i
      # Vendors escape non-BMP characters (emoji) as a UTF-16 surrogate pair,
      # so the two halves have to be recombined; packing either half on its own
      # yields bytes that are not valid UTF-8.
      HIGH_SURROGATE = (0xD800..0xDBFF)
      LOW_SURROGATE = (0xDC00..0xDFFF)
      SURROGATE_OFFSET = 0x10000

      SIMPLE_ESCAPES = {
        '"' => '"', "\\" => "\\", "/" => "/",
        "n" => "\n", "t" => "\t", "r" => "\r", "b" => "\b", "f" => "\f"
      }.freeze

      module_function

      # @return [String] prose so far; "" while the document has not reached
      #   its `reply` value yet.
      def visible(raw)
        text = raw.to_s.sub(FENCE, "")
        return "" if text.strip.empty?

        # Keyed on the reply itself rather than a leading brace: a model that
        # prefixes the document with prose ("Sure! {...}") would otherwise have
        # its whole wire object — intent, document, effects — put on screen.
        match = REPLY_KEY.match(text)
        return scan(text, match.end(0)) if match

        # A document that has started but not reached its reply yet has nothing
        # to show; a model that answered in prose instead is shown verbatim.
        return "" if text.lstrip.start_with?("{")

        text.strip
      end

      # Walks the string body from `from`, stopping at the closing quote or at
      # the first escape that has not fully arrived.
      def scan(text, from)
        out = +""
        index = from
        length = text.length

        while index < length
          char = text[index]
          case char
          when '"' then return out
          when "\\"
            decoded, width = unescape(text, index)
            return out if decoded.nil?

            out << decoded
            index += width
          else
            out << char
            index += 1
          end
        end

        out
      end

      # @return [Array(String, Integer), Array(nil, nil)] the decoded character
      #   and how many source characters it consumed, or nils when the escape
      #   is still being transmitted.
      def unescape(text, index)
        marker = text[index + 1]
        return [ nil, nil ] if marker.nil?

        simple = SIMPLE_ESCAPES[marker]
        return [ simple, 2 ] if simple

        return [ marker, 2 ] unless marker == "u"

        code = hex_at(text, index)
        return [ nil, nil ] if code.nil?
        return [ [ code ].pack("U"), 6 ] unless HIGH_SURROGATE.cover?(code)

        paired(text, index, code)
      end

      # A high surrogate is only meaningful with its low half. A half that has
      # not arrived yet is treated as a truncated escape; one that never comes
      # is dropped, because packing it alone would poison the whole string.
      def paired(text, index, high)
        return [ nil, nil ] if text.length < index + 12

        low = text[index + 6, 2] == "\\u" ? hex_at(text, index + 6) : nil
        return [ "", 6 ] unless low && LOW_SURROGATE.cover?(low)

        combined = SURROGATE_OFFSET + ((high - 0xD800) << 10) + (low - 0xDC00)
        [ [ combined ].pack("U"), 12 ]
      end

      # @return [Integer, nil] the code point of the \uXXXX escape at `index`,
      #   or nil when its four hex digits have not all arrived.
      def hex_at(text, index)
        hex = text[index + 2, 4]
        return nil unless hex&.length == 4 && hex.match?(/\A\h{4}\z/)

        hex.hex
      end
    end
  end
end
