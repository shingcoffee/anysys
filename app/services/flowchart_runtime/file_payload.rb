# frozen_string_literal: true

require "marcel"
require "stringio"

module FlowchartRuntime
  # Canonical in-memory file shape shared by generate_file, download_file,
  # compress_files, decompress_files, upload_file, and send_email attachments:
  #
  #   { "filename" => "orders.csv", "content" => "<bytes>", "content_type" => "text/csv" }
  #
  # MailAttachments accepts the bytes as a Hash value keyed by filename, or a
  # Hash with :content / :data / :body. upload_file reads this shape (or raw
  # bytes) from sourceVariable.
  module FilePayload
    class Error < StandardError; end

    CONTENT_TYPES = {
      "csv" => "text/csv",
      "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "json" => "application/json",
      "txt" => "text/plain",
      "zip" => "application/zip",
      "gz" => "application/gzip",
      "tar" => "application/x-tar",
      "tar_gz" => "application/gzip"
    }.freeze

    module_function

    def wrap(content, filename:, content_type: nil)
      bytes = content.to_s.b
      name = File.basename(filename.to_s.presence || "file.bin")
      name = "file.bin" if name.blank? || name == "." || name == ".."
      type = content_type.to_s.presence || sniff(bytes, filename: name)
      { "filename" => name, "content" => bytes, "content_type" => type }
    end

    def wrap_entries(entries)
      Array(entries).map do |entry|
        hash = entry.is_a?(Hash) ? entry : {}
        name = hash[:name] || hash["name"] || hash[:filename] || hash["filename"]
        body = hash.key?(:content) || hash.key?("content") ? (hash[:content] || hash["content"]) : entry
        wrap(body, filename: name)
      end
    end

    def extract(value)
      case value
      when Hash
        content = value["content"] || value[:content] || value["data"] || value[:data] ||
                  value["body"] || value[:body]
        {
          content: content.to_s.b,
          filename: (value["filename"] || value[:filename]).to_s.presence,
          content_type: (value["content_type"] || value[:content_type]).to_s.presence
        }
      when nil
        { content: "".b, filename: nil, content_type: nil }
      else
        { content: value.to_s.b, filename: nil, content_type: nil }
      end
    end

    def bytes(value)
      extract(value)[:content]
    end

    def sniff(content, filename: nil, declared_type: nil)
      Marcel::MimeType.for(
        StringIO.new(content.to_s.b),
        name: filename.to_s.presence,
        declared_type: declared_type.to_s.presence
      )
    end
  end
end
