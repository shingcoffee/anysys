# frozen_string_literal: true

require "open3"
require "tempfile"
require "timeout"

module SpeechToText
  # FFmpeg is the mature decoder: count its fixed-rate PCM output, never
  # container duration metadata or client timestamps. Restrict protocols to
  # local files/pipes so a crafted playlist cannot fetch remote resources.
  class AudioProbe
    SAMPLE_RATE = 8_000
    BYTES_PER_SECOND = SAMPLE_RATE * 2
    TIMEOUT = 30
    class InvalidAudio < StandardError; end
    class Unavailable < StandardError; end
    class TooLong < StandardError; end

    def self.call(upload:, max_duration:)
      new(upload: AudioUpload.wrap(upload), max_duration: max_duration).call
    end

    def initialize(upload:, max_duration:)
      @upload = upload
      @max_duration = max_duration
    end

    def call
      Tempfile.create(["stt-probe", ".audio"]) do |file|
        file.binmode
        source = @upload.io
        source = source.tempfile if source.respond_to?(:tempfile)
        unless source.respond_to?(:read) && source.respond_to?(:rewind)
          raise InvalidAudio, "unreadable audio"
        end
        source.rewind
        copied = IO.copy_stream(source, file, Contracts::Transcription::MAX_AUDIO_BYTES + 1)
        raise InvalidAudio, "audio byte cap" if copied > Contracts::Transcription::MAX_AUDIO_BYTES

        file.flush
        decode(file.path)
      ensure
        source.rewind if source.respond_to?(:rewind)
      end
    rescue Errno::ENOENT, Errno::EACCES => e
      raise Unavailable, e.class.name
    rescue Timeout::Error, IOError => e
      raise InvalidAudio, e.class.name
    end

    private

    def decode(path)
      command = [ENV.fetch("STT_FFMPEG_PATH", "ffmpeg"), "-nostdin", "-v", "error", "-xerror",
                 "-protocol_whitelist", "file,pipe", "-threads", "1", "-i", path,
                 "-map", "0:a:0", "-vn", "-sn", "-dn", "-ac", "1", "-ar", SAMPLE_RATE.to_s,
                 "-f", "s16le", "pipe:1"]
      Open3.popen3(*command) do |stdin, stdout, stderr, waiter|
        stdin.close
        # Drain stderr without accumulating an attacker-controlled log.
        error_reader = Thread.new { IO.copy_stream(stderr, File::NULL) }
        bytes = 0
        begin
          Timeout.timeout(TIMEOUT) do
            loop do
              bytes += stdout.readpartial(16_384).bytesize
              raise TooLong, "decoded audio duration cap" if bytes > @max_duration * BYTES_PER_SECOND
            rescue EOFError
              break
            end
            raise InvalidAudio, "audio decode failed" unless waiter.value.success? && bytes.positive?
          end
          bytes.fdiv(BYTES_PER_SECOND)
        ensure
          stop(waiter)
          waiter.join
          error_reader.join
        end
      end
    end

    def stop(waiter)
      Process.kill("KILL", waiter.pid) if waiter.alive?
    rescue Errno::ESRCH
      nil
    end
  end
end
