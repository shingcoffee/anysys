# frozen_string_literal: true

require "digest"
require "stringio"
require "uri"

module FlowchartRuntime
  module FileDownload
    class Error < StandardError; end

    CHECKSUM_ALGOS = %w[sha256 md5].freeze
    DEFAULT_MAX_BYTES = 25.megabytes
    MAX_BYTES = 100.megabytes

    module_function

    def fetch(ctx, url, headers: {}, open_timeout: 3, read_timeout: 7,
              retries: 0, breaker: nil, follow_redirects: true, max_redirects: 3,
              max_bytes: nil, checksum: nil, allowed_content_types: [])
      raise Error, "url is required" if url.to_s.strip.empty?

      limit = clamp_max_bytes(max_bytes)
      response = Http.request(
        ctx,
        :get,
        url,
        headers: headers.to_h,
        open_timeout: open_timeout,
        read_timeout: read_timeout,
        retries: retries,
        breaker: breaker,
        follow_redirects: follow_redirects,
        max_redirects: max_redirects,
        max_bytes: limit
      )
      return false unless response

      enforce_content_type!(response, allowed_content_types)
      data = response.body.to_s
      verify_checksum!(data, checksum) if checksum.to_s.present?
      FilePayload.wrap(
        data,
        filename: filename_for(url),
        content_type: response_content_type(response)
      )
    rescue Http::Error, URI::InvalidURIError => error
      raise Error, error.message
    end

    def clamp_max_bytes(max_bytes)
      n = Integer(max_bytes, exception: false)
      n = DEFAULT_MAX_BYTES if n.nil? || !n.positive?
      [n, MAX_BYTES].min
    end

    def filename_for(url)
      name = File.basename(URI.parse(url.to_s).path.to_s)
      name = "download.bin" if name.blank? || name == "/" || name == "." || name == ".."
      name
    rescue URI::InvalidURIError
      "download.bin"
    end

    def response_content_type(response)
      headers = response.respond_to?(:headers) ? response.headers : {}
      raw = header_lookup(headers, "content-type").to_s
      raw.split(";", 2).first.to_s.strip.presence
    end

    def enforce_content_type!(response, allowed)
      types = Array(allowed).map { |item| item.to_s.strip.downcase }.reject(&:empty?)
      return if types.empty?

      actual = response_content_type(response).to_s.downcase
      return if types.any? { |allowed_type| content_type_match?(actual, allowed_type) }

      raise Error, "content type is not allowed"
    end

    def header_lookup(headers, name)
      return if headers.nil?
      return headers[name] if headers.respond_to?(:[]) && headers[name]
      return headers[name.downcase] if headers.respond_to?(:[]) && headers[name.downcase]

      title = name.split("-").map(&:capitalize).join("-")
      headers[title] if headers.respond_to?(:[])
    end

    def content_type_match?(actual, allowed)
      return true if actual == allowed
      return true if actual.start_with?("#{allowed}+")

      File.fnmatch?(allowed, actual)
    end
    private_class_method :enforce_content_type!, :header_lookup, :content_type_match?,
                         :clamp_max_bytes, :filename_for, :response_content_type

    def verify_checksum!(data, expected)
      raw = expected.to_s.strip
      algo, digest = if raw.include?(":")
                       raw.split(":", 2)
                     else
                       [raw.length == 32 ? "md5" : "sha256", raw]
                     end
      raise Error, "invalid checksum" unless CHECKSUM_ALGOS.include?(algo.to_s) && digest.to_s.match?(/\A[0-9a-fA-F]+\z/)

      actual = algo == "md5" ? Digest::MD5.hexdigest(data) : Digest::SHA256.hexdigest(data)
      raise Error, "checksum mismatch" unless actual.casecmp?(digest)
    end
  end
end
