# frozen_string_literal: true

module SpeechToText
  # Single source of truth for the audio this module accepts.
  #
  # Three places used to keep their own idea of "supported audio": the upload
  # contract (a loose `audio/*` prefix test), Aliyun#audio_format, and the
  # former AWS batch MediaFormat. They could — and did — disagree, which let
  # bytes the contract accepted reach a vendor that could not decode them.
  #
  # Aliyun Flash keys its decoder on a vendor format token; AWS Transcribe
  # Streaming transcodes every accepted family to PCM, so it does not read
  # these tokens. They stay on the family so a future batch path (or docs)
  # can still name the container AWS would have expected.
  #
  # `bytes_per_second` is a deliberately generous WORST-CASE bitrate for the
  # family, used to derive a byte ceiling from the tenant's duration cap (see
   # .max_bytes_for). It is a request-size guard, not a duration measurement:
   # AudioProbe enforces the duration policy from decoded samples.
  module AudioFormats
    # 512 kbps. No speech codec the dictate widget or desktop client can emit
    # comes close; anything above this for a given duration is a lying client.
    COMPRESSED_BYTES_PER_SECOND = 64.kilobytes
    # 48 kHz / 16-bit / stereo linear PCM — the worst case for a raw container.
    UNCOMPRESSED_BYTES_PER_SECOND = 192.kilobytes

    FAMILIES = {
      webm: {
        mime:             %w[audio/webm video/webm],
        extensions:       %w[webm],
        aws:              "webm",
        aliyun:           "opus",
        bytes_per_second: COMPRESSED_BYTES_PER_SECOND
      },
      ogg: {
        mime:             %w[audio/ogg audio/opus audio/x-opus+ogg application/ogg],
        extensions:       %w[ogg oga opus],
        aws:              "ogg",
        aliyun:           "opus",
        bedrock:          "ogg",
        bytes_per_second: COMPRESSED_BYTES_PER_SECOND
      },
      wav: {
        mime:             %w[audio/wav audio/wave audio/x-wav audio/vnd.wave],
        extensions:       %w[wav],
        aws:              "wav",
        aliyun:           "wav",
        bedrock:          "wav",
        bytes_per_second: UNCOMPRESSED_BYTES_PER_SECOND
      },
      mpeg: {
        mime:             %w[audio/mpeg audio/mp3 audio/mpeg3 audio/x-mpeg-3],
        extensions:       %w[mp3],
        aws:              "mp3",
        aliyun:           "mp3",
        bedrock:          "mp3",
        bytes_per_second: COMPRESSED_BYTES_PER_SECOND
      },
      mp4: {
        mime:             %w[audio/mp4],
        extensions:       %w[mp4],
        aws:              "mp4",
        aliyun:           "mp4",
        bedrock:          "mp4",
        bytes_per_second: COMPRESSED_BYTES_PER_SECOND
      },
      m4a: {
        mime:             %w[audio/m4a audio/x-m4a],
        extensions:       %w[m4a],
        aws:              "m4a",
        aliyun:           "mp4",
        bedrock:          "mp4",
        bytes_per_second: COMPRESSED_BYTES_PER_SECOND
      },
      aac: {
        mime:             %w[audio/aac audio/aacp audio/x-aac],
        extensions:       %w[aac],
        aws:              "mp4",
        aliyun:           "aac",
        bedrock:          "aac",
        bytes_per_second: COMPRESSED_BYTES_PER_SECOND
      },
      flac: {
        mime:             %w[audio/flac audio/x-flac],
        extensions:       %w[flac],
        aws:              "flac",
        aliyun:           "wav",
        bedrock:          "flac",
        bytes_per_second: UNCOMPRESSED_BYTES_PER_SECOND
      },
      amr: {
        mime:             %w[audio/amr audio/3gpp],
        extensions:       %w[amr],
        aws:              "amr",
        aliyun:           "wav",
        bytes_per_second: COMPRESSED_BYTES_PER_SECOND
      }
    }.freeze

    MIME_TYPES = FAMILIES.values.flat_map { |spec| spec[:mime] }.freeze
    EXTENSIONS = FAMILIES.values.flat_map { |spec| spec[:extensions] }.freeze

    class << self
      # MediaRecorder emits parameterised types such as
      # "audio/webm;codecs=opus" — match on the bare type only.
      def permitted_mime?(content_type)
        MIME_TYPES.include?(normalize_mime(content_type))
      end

      def normalize_mime(content_type)
        content_type.to_s.split(";").first.to_s.strip.downcase
      end

      # The extension wins over the declared MIME type: a browser's Content-Type
      # is a hint, while the extension is what both vendors key their decoder on.
      def family(filename: nil, content_type: nil)
        family_for_extension(filename) || family_for_mime(content_type)
      end

      def vendor_format(vendor, filename: nil, content_type: nil, default: nil)
        key = family(filename: filename, content_type: content_type)
        return default unless key

        FAMILIES.dig(key, vendor) || default
      end

      # Byte ceiling implied by a duration cap. AudioProbe separately rejects
      # long compressed clips that fit this ceiling.
      def max_bytes_for(seconds, filename: nil, content_type: nil)
        seconds.to_i * bytes_per_second(filename: filename, content_type: content_type)
      end

      # Deliberately NOT `family`'s extension-wins rule. Both the filename and
      # the declared Content-Type come from the client, so honouring one alone
      # lets a caller pick its own ceiling: naming a webm body "clip.wav" would
      # buy the uncompressed rate, roughly 3x the room. Taking the lower of the
      # two rates means a mismatched pair can only ever tighten the limit.
      def bytes_per_second(filename: nil, content_type: nil)
        rates = [ family_for_extension(filename), family_for_mime(content_type) ]
          .compact
          .filter_map { |key| FAMILIES.dig(key, :bytes_per_second) }

        rates.min || UNCOMPRESSED_BYTES_PER_SECOND
      end

      private

      def family_for_extension(filename)
        ext = File.extname(filename.to_s).delete(".").downcase
        return nil if ext.blank?

        FAMILIES.find { |_key, spec| spec[:extensions].include?(ext) }&.first
      end

      def family_for_mime(content_type)
        mime = normalize_mime(content_type)
        return nil if mime.blank?

        FAMILIES.find { |_key, spec| spec[:mime].include?(mime) }&.first
      end
    end
  end
end
