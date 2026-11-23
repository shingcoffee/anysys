# frozen_string_literal: true

require "zip"
require "zlib"
require "rubygems/package"
require "stringio"
require "pathname"

module FlowchartRuntime
  # FlowchartRuntime::Archive
  #
  # Thin wrapper around rubyzip, Zlib, and RubyGems tar for flowchart
  # compress/decompress step generators. Owns allowed formats and a single
  # error type (FlowchartRuntime::Archive::Error) so generated step code
  # never rescues raw Zip/Zlib/Gem::Package exceptions.
  module Archive
    class Error < StandardError; end

    FORMATS = %i[zip gzip tar tar_gz].freeze
    MAX_INPUT_BYTES = 25.megabytes
    MAX_OUTPUT_BYTES = 100.megabytes
    MAX_ENTRY_BYTES = 25.megabytes
    MAX_ENTRIES = 1_000
    READ_CHUNK_BYTES = 64.kilobytes

    module_function

    # @param entries           [Array<Hash>] each hash has :name and :content
    # @param format            [Symbol, String] one of FORMATS (also accepts "gz" for :gzip)
    # @param compression_level [Integer, nil] 0-9 for zip/gzip/tar_gz
    # @return [String] binary archive payload
    # @raise  [FlowchartRuntime::Archive::Error]
    def compress(entries, format: :zip, compression_level: nil)
      fmt = normalize_format(format)
      raise Error, "unsupported format" unless FORMATS.include?(fmt)
      level = normalize_compression_level(compression_level)

      normalized = normalize_entries(entries)

      archive = case fmt
      when :zip then compress_zip(normalized, compression_level: level)
      when :gzip then compress_gzip(normalized, compression_level: level)
      when :tar then compress_tar(normalized)
      when :tar_gz then compress_tar_gz(normalized, compression_level: level)
      end
      raise Error, "archive input exceeds #{MAX_INPUT_BYTES} bytes" if archive.bytesize > MAX_INPUT_BYTES

      archive
    rescue Zip::Error, Zlib::Error, Gem::Package::TarInvalidError => e
      raise Error, e.message
    end

    # @param payload    [String] binary archive
    # @param format     [Symbol, String]
    # @param gzip_name  [String, nil] filename for single-file gzip decompress
    # @return [Array<Hash>] entries with :name and :content
    # @raise  [FlowchartRuntime::Archive::Error]
    def decompress(payload, format: :zip, gzip_name: nil, max_entries: nil, max_total_bytes: nil)
      fmt = normalize_format(format)
      raise Error, "unsupported format" unless FORMATS.include?(fmt)
      data = payload.to_s.b
      raise Error, "archive input exceeds #{MAX_INPUT_BYTES} bytes" if data.bytesize > MAX_INPUT_BYTES
      entries_cap = clamp_cap(max_entries, MAX_ENTRIES)
      bytes_cap = clamp_cap(max_total_bytes, MAX_OUTPUT_BYTES)

      case fmt
      when :zip then decompress_zip(data, max_entries: entries_cap, max_total_bytes: bytes_cap)
      when :gzip then decompress_gzip(data, gzip_name: gzip_name, max_total_bytes: bytes_cap)
      when :tar then decompress_tar(data, max_entries: entries_cap, max_total_bytes: bytes_cap)
      when :tar_gz then decompress_tar_gz(data, max_entries: entries_cap, max_total_bytes: bytes_cap)
      end
    rescue Zip::Error, Zlib::Error, Gem::Package::TarInvalidError, EOFError => e
      raise Error, e.message
    end

    def pack(ctx, sources: {}, literals: {}, format: :zip, compression_level: nil, include_hidden: false, filename: nil)
      entries = []
      Hash(sources).each do |name, key|
        next if skip_hidden?(name, include_hidden)

        validate_entry_name!(name)
        entries << { name: name.to_s, content: FilePayload.bytes(lookup_ctx(ctx, key)) }
      end
      Hash(literals).each do |name, content|
        next if skip_hidden?(name, include_hidden)

        validate_entry_name!(name)
        entries << { name: name.to_s, content: content.to_s }
      end
      raise Error, "entries are required" if entries.empty?

      fmt = normalize_format(format)
      bytes = compress(entries, format: fmt, compression_level: compression_level)
      FilePayload.wrap(
        bytes,
        filename: filename.presence || default_archive_name(fmt),
        content_type: FilePayload::CONTENT_TYPES[fmt.to_s] || FilePayload::CONTENT_TYPES["zip"]
      )
    end

    def unpack(payload, format: "auto", filter: nil, gzip_name: nil, max_entries: nil, max_total_bytes: nil)
      extracted = FilePayload.extract(payload)
      data = extracted[:content]
      gzip_name = gzip_name.presence || extracted[:filename]
      fmt = format.to_s == "auto" ? detect_format(data, gzip_name) : format
      entries = decompress(
        data,
        format: fmt,
        gzip_name: gzip_name,
        max_entries: max_entries,
        max_total_bytes: max_total_bytes
      )
      result = []
      entries.each do |entry|
        validate_entry_name!(entry[:name])
        SandboxPath.join_under(SandboxPath::EXTRACT_ROOT, File.basename(entry[:name].to_s))
        next if filter.to_s.present? && !File.fnmatch(filter.to_s, entry[:name].to_s)

        result << FilePayload.wrap(entry[:content], filename: entry[:name])
      end
      result
    end

    def detect_format(payload, gzip_name = nil)
      bytes = FilePayload.bytes(payload).to_s.byteslice(0, 4).to_s.b
      if bytes.start_with?("PK\x03\x04".b) || bytes.start_with?("PK\x05\x06".b)
        "zip"
      elsif bytes.start_with?("\x1F\x8B".b)
        name = gzip_name.to_s
        name.end_with?(".tar.gz", ".tgz") ? "tar_gz" : "gz"
      else
        "tar"
      end
    end

    def skip_hidden?(name, include_hidden)
      return false if include_hidden

      File.basename(name.to_s).start_with?(".")
    end

    def lookup_ctx(ctx, key)
      name = key.to_s
      return ctx[name] if ctx.respond_to?(:key?) && ctx.key?(name)
      return ctx[name.to_sym] if ctx.respond_to?(:key?) && ctx.key?(name.to_sym)

      nil
    end

    def normalize_format(format)
      case format.to_s
      when "zip" then :zip
      when "gzip", "gz" then :gzip
      when "tar" then :tar
      when "tar_gz", "tar.gz" then :tar_gz
      else format.to_s.to_sym
      end
    end

    def normalize_compression_level(compression_level)
      return nil if compression_level.nil?

      level = Integer(compression_level, exception: false)
      raise Error, "compression level must be between 0 and 9" unless level && (0..9).cover?(level)

      level
    end

    def normalize_entries(entries)
      values = Array(entries)
      raise Error, "too many entries (maximum #{MAX_ENTRIES})" if values.size > MAX_ENTRIES

      total_bytes = 0
      values.map do |entry|
        raise Error, "entry must be a hash" unless entry.is_a?(Hash)

        name = entry[:name] || entry["name"] || "file.dat"
        validate_entry_name!(name)
        content = if entry.key?(:content)
                    entry[:content]
                  elsif entry.key?("content")
                    entry["content"]
                  else
                    ""
                  end
        data = content.to_s.b
        raise Error, "entry exceeds #{MAX_ENTRY_BYTES} bytes" if data.bytesize > MAX_ENTRY_BYTES
        total_bytes += data.bytesize
        raise Error, "expanded data exceeds #{MAX_OUTPUT_BYTES} bytes" if total_bytes > MAX_OUTPUT_BYTES

        { name: name.to_s, content: data }
      end
    end

    def validate_entry_name!(name)
      value = name.to_s
      normalized = value.tr("\\", "/")
      segments = normalized.split("/")
      unsafe = value.include?("\0") ||
               normalized.start_with?("/") ||
               normalized.match?(/\A[A-Za-z]:\//) ||
               segments.include?("..") ||
               Pathname.new(normalized).absolute?
      raise Error, "path traversal detected in #{value}" if unsafe

      value
    end

    def compress_zip(entries, compression_level:)
      if compression_level
        previous = Zip.default_compression
        Zip.default_compression = compression_level.to_i
      end

      buffer = StringIO.new
      Zip::OutputStream.write_buffer(buffer) do |stream|
        entries.each do |entry|
          stream.put_next_entry(entry[:name])
          stream.write(entry[:content])
        end
      end
      buffer.string
    ensure
      Zip.default_compression = previous if compression_level
    end

    def compress_gzip(entries, compression_level:)
      raise Error, "gzip requires exactly one entry" unless entries.one?

      entry = entries.first
      buffer = StringIO.new
      gz = compression_level ? Zlib::GzipWriter.new(buffer, compression_level.to_i) : Zlib::GzipWriter.new(buffer)
      gz.orig_name = entry[:name]
      gz.write(entry[:content])
      gz.close
      buffer.string
    end

    def compress_tar(entries)
      buffer = StringIO.new
      Gem::Package::TarWriter.new(buffer) do |tar|
        entries.each do |entry|
          data = entry[:content]
          tar.add_file_simple(entry[:name], 0o644, data.bytesize) { |io| io.write(data) }
        end
      end
      buffer.string
    end

    def compress_tar_gz(entries, compression_level:)
      buffer = StringIO.new
      gz = compression_level ? Zlib::GzipWriter.new(buffer, compression_level.to_i) : Zlib::GzipWriter.new(buffer)
      Gem::Package::TarWriter.new(gz) do |tar|
        entries.each do |entry|
          data = entry[:content]
          tar.add_file_simple(entry[:name], 0o644, data.bytesize) { |io| io.write(data) }
        end
      end
      gz.close
      buffer.string
    end

    def decompress_zip(payload, max_entries: MAX_ENTRIES, max_total_bytes: MAX_OUTPUT_BYTES)
      data = payload.to_s.b
      unless data.start_with?("PK\x03\x04".b) || data.start_with?("PK\x05\x06".b)
        raise Error, "invalid zip archive"
      end

      entries = []
      total_bytes = 0
      entry_count = 0
      Zip::InputStream.open(StringIO.new(data)) do |stream|
        while (entry = stream.get_next_entry)
          entry_count += 1
          enforce_entry_count!(entry_count, max_entries)
          next if entry.directory?

          content = read_limited(stream, total_bytes:, max_total_bytes: max_total_bytes)
          total_bytes += content.bytesize
          entries << { name: entry.name, content: }
        end
      end
      entries
    end

    def decompress_gzip(payload, gzip_name:, max_total_bytes: MAX_OUTPUT_BYTES)
      data = payload.to_s.b
      raise Error, "invalid gzip archive" unless data.start_with?("\x1F\x8B".b)

      reader = Zlib::GzipReader.new(StringIO.new(data))
      raw = read_limited(reader, total_bytes: 0, max_total_bytes: max_total_bytes)
      reject_trailing_gzip_data!(reader)

      name = gzip_name.to_s.sub(/\.gz\z/, "")
      name = "decompressed" if name.empty?
      [{ name: name, content: raw.to_s.b }]
    end

    def decompress_tar(payload, max_entries: MAX_ENTRIES, max_total_bytes: MAX_OUTPUT_BYTES)
      entries = []
      total_bytes = 0
      entry_count = 0
      Gem::Package::TarReader.new(StringIO.new(payload.to_s.b)) do |tar|
        tar.each do |entry|
          entry_count += 1
          enforce_entry_count!(entry_count, max_entries)
          next if entry.directory?

          content = read_limited(entry, total_bytes:, max_total_bytes: max_total_bytes)
          total_bytes += content.bytesize
          entries << { name: entry.full_name, content: }
        end
      end
      entries
    end

    def decompress_tar_gz(payload, max_entries: MAX_ENTRIES, max_total_bytes: MAX_OUTPUT_BYTES)
      io = Zlib::GzipReader.new(StringIO.new(payload.to_s.b))
      tar_payload = read_limited(io, total_bytes: 0, enforce_entry_limit: false, max_total_bytes: max_total_bytes)
      reject_trailing_gzip_data!(io)
      decompress_tar(tar_payload, max_entries: max_entries, max_total_bytes: max_total_bytes)
    end

    def read_limited(io, total_bytes:, enforce_entry_limit: true, max_total_bytes: MAX_OUTPUT_BYTES)
      output = +"".b
      while (chunk = io.read(READ_CHUNK_BYTES))
        output << chunk.to_s.b
        raise Error, "expanded data exceeds #{max_total_bytes} bytes" if total_bytes + output.bytesize > max_total_bytes
        if enforce_entry_limit && output.bytesize > MAX_ENTRY_BYTES
          raise Error, "entry exceeds #{MAX_ENTRY_BYTES} bytes"
        end
      end
      output
    end

    def enforce_entry_count!(count, max_entries = MAX_ENTRIES)
      raise Error, "too many entries (maximum #{max_entries})" if count > max_entries
    end

    def clamp_cap(value, ceiling)
      n = Integer(value, exception: false)
      return ceiling if n.nil? || !n.positive?

      [n, ceiling].min
    end

    def reject_trailing_gzip_data!(reader)
      raise Error, "multiple gzip members are not supported" if reader.unused.to_s.bytesize.positive?
    end

    def default_archive_name(format)
      case format.to_s
      when "gzip", "gz" then "archive.gz"
      when "tar" then "archive.tar"
      when "tar_gz", "tar.gz" then "archive.tar.gz"
      else "archive.zip"
      end
    end
    private_class_method :default_archive_name
  end
end
