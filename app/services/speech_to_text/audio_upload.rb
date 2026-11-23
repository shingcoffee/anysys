# frozen_string_literal: true

module SpeechToText
  # Normalises the shapes a dictation upload arrives in — a Rack/Rails uploaded
  # file, an `{ io:, filename:, content_type: }` hash, or a bare IO — behind one
  # interface so the contract, the enqueue activity and ActiveStorage all read
  # exactly the same filename, MIME type and byte size.
  #
  # Every reader returns nil when the value is genuinely unknown rather than a
  # permissive default: callers MUST fail closed on a missing MIME type or
  # byte size instead of waving unverified bytes through to a paid vendor.
  class AudioUpload
    # Only used to name the ActiveStorage blob once validation has passed; it is
    # never substituted for a missing client-declared MIME type.
    FALLBACK_FILENAME = "dictation.webm"

    attr_reader :source

    def self.wrap(source)
      source.is_a?(self) ? source : new(source)
    end

    def initialize(source)
      @source = source
    end

    def present?
      io.present?
    end

    def blank?
      !present?
    end

    def io
      return nil if source.blank?
      return hash_value(:io) if hash?

      source
    end

    def filename
      return hash_value(:filename) if hash?
      return source.original_filename if source.respond_to?(:original_filename)

      nil
    end

    # nil when the client sent no Content-Type — the contract rejects that
    # rather than guessing.
    def content_type
      value = hash? ? hash_value(:content_type) : (source.content_type if source.respond_to?(:content_type))
      value.presence
    end

    # nil when neither the IO nor the attachment can report a length, so the
    # size cap cannot be silently skipped.
    def byte_size
      target = io
      return nil if target.nil?
      return target.size if target.respond_to?(:size)
      return target.byte_size if target.respond_to?(:byte_size)

      nil
    end

    def attach_to(attachment)
      if uploaded_file?
        attachment.attach(source)
      else
        attachment.attach(
          io: io,
          filename: filename.presence || FALLBACK_FILENAME,
          content_type: content_type
        )
      end
    end

    private

    def hash?
      source.is_a?(Hash)
    end

    def hash_value(key)
      source[key] || source[key.to_s]
    end

    def uploaded_file?
      source.respond_to?(:tempfile) || source.is_a?(ActionDispatch::Http::UploadedFile)
    end
  end
end
