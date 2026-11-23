# frozen_string_literal: true

require "faraday"
require "faraday/multipart"
require "resolv"
require "uri"

# OutboundHttp
#
# Single app-level entry point for outbound HTTP, backed by the Faraday gem
# (per AGENTS.md: prefer a mature library over hand-rolled protocol code, and
# wrap it behind one thin service so it can be swapped without touching
# callers). All vendor transports (payment gateways, SMS adapters, captcha
# providers, flowchart API-call steps) go through here instead of hand-rolling
# Net::HTTP plumbing.
#
# Responsibilities:
#   - method dispatch, TLS, JSON/form body encoding
#   - explicit open/read timeouts on every request (no unbounded sockets)
#   - normalising Faraday transport failures into OutboundHttp::TransportError
#     (callers re-wrap into their module-specific error class)
#
# Deliberately NOT here: vendor signing, retries, response-body parsing —
# those stay caller-owned so this wrapper has a single stable responsibility.
#
# @example JSON POST
#   res = OutboundHttp.request(:post, url, headers: { "Accept" => "application/json" },
#                              body: { amount: 100 }, open_timeout: 5, read_timeout: 30)
#   res.status    # => 200 (Integer)
#   res.code      # => "200" (String, Net::HTTP-compatible)
#   res.body      # => raw body String
#   res.success?  # => true
#
# @example form POST
#   OutboundHttp.request(:post, url, form: { a: 1 })
#
class OutboundHttp
  DEFAULT_OPEN_TIMEOUT = 5
  DEFAULT_READ_TIMEOUT = 15
  REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze
  ALLOWED_METHODS = %i[get post put patch delete head options].freeze
  SENSITIVE_REDIRECT_HEADER = /\A(?:authorization|proxy-authorization|cookie|cookie2|.*(?:api[-_]?key|token|secret|signature).*)\z/i
  CONTENT_HEADERS = %w[content-type content-length transfer-encoding].freeze

  class Error < StandardError; end
  class InvalidRequestError < Error; end
  class BlockedDestinationError < InvalidRequestError; end
  class RedirectError < Error; end
  class ResponseTooLargeError < Error; end

  class ResponseError < Error
    attr_reader :response

    def initialize(response)
      @response = response
      super("HTTP request failed with status #{response.status}")
    end
  end

  # Raised for any network-level failure (DNS, connect/read timeout, refused
  # connection, TLS failure). Wraps the underlying Faraday error as +cause+.
  class TransportError < Error
    # True when the failure was a connect/read timeout (vs. e.g. DNS/refused).
    def timeout?
      cause.is_a?(Faraday::TimeoutError) ||
        cause&.cause.is_a?(Net::OpenTimeout) || cause&.cause.is_a?(Net::ReadTimeout)
    end
  end

  # Immutable transport-level response. Exposes both Integer #status and the
  # Net::HTTP-compatible String #code so existing vendor call sites keep working.
  Response = Data.define(:status, :headers, :body) do
    def code       = status.to_s
    def success?   = (200..299).cover?(status)
    def redirect?  = (300..399).cover?(status)
  end

  class << self
    # @param method       [Symbol, String] :get, :post, :put, :patch, :delete
    # @param url          [String]
    # @param headers      [Hash]
    # @param body         [String, Hash, nil] raw string sent as-is; Hash is JSON-encoded
    # @param form         [Hash, nil] URL-encoded form body (overrides +body+)
    # @param open_timeout [Numeric]
    # @param read_timeout [Numeric]
    # @param follow_redirects [Boolean] when true, follow 3xx Location headers
    # @param max_redirects [Integer] max redirect hops to follow; after exhausting
    #   hops, returns the redirect response that was not followed
    # @param public_only [Boolean] when true, refuse non-public destinations on
    #   the initial URL and every redirect hop, and pin TCP to a validated IP
    # @return [OutboundHttp::Response]
    # @raise  [OutboundHttp::TransportError]
    def request(method, url, headers: {}, body: nil, form: nil, multipart: nil,
                open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                follow_redirects: false, max_redirects: 5, public_only: false)
      current_method = normalize_method(method)
      current_url = normalize_url(url)
      remaining = normalize_redirect_limit(max_redirects)
      open_timeout = normalize_timeout(open_timeout, "open_timeout")
      read_timeout = normalize_timeout(read_timeout, "read_timeout")
      current_body, body_mode = encode_body(body:, form:, multipart:)
      current_headers = request_headers(headers, body_mode)
      response = nil

      loop do
        pinned_ip = public_only ? assert_public_destination!(current_url) : nil
        rewind_multipart_uploads!(current_body) if body_mode == :multipart
        response = connection(open_timeout:, read_timeout:, pinned_ip:).run_request(
          current_method, current_url, current_body, current_headers
        )
        break unless follow_redirects && REDIRECT_STATUSES.include?(response.status)

        location = response.headers["location"] || response.headers["Location"]
        break if location.blank?
        raise RedirectError, "maximum redirects exceeded" unless remaining.positive?

        next_url = redirect_location(current_url, location)
        current_headers = redirect_headers(current_headers, from: current_url, to: next_url)
        current_method, current_body, current_headers =
          redirect_request(response.status, current_method, current_body, current_headers)
        current_url = next_url
        remaining -= 1
      end

      Response.new(status: response.status, headers: response.headers.to_h, body: response.body.to_s)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError => e
      raise TransportError, e.message
    rescue URI::InvalidURIError => e
      raise InvalidRequestError, e.message
    end

    # Streams a response through Faraday's adapter-level on_data callback.
    # The adapter never retains the full response body; callers receive each
    # chunk only after the incremental byte limit has been checked.
    # +public_only+ applies the same per-hop guard and IP pinning as #request.
    def stream(method, url, headers: {}, body: nil, form: nil, multipart: nil,
               open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
               follow_redirects: false, max_redirects: 5, max_bytes: nil, public_only: false, &on_chunk)
      raise InvalidRequestError, "stream block is required" unless on_chunk

      current_method = normalize_method(method)
      current_url = normalize_url(url)
      remaining = normalize_redirect_limit(max_redirects)
      open_timeout = normalize_timeout(open_timeout, "open_timeout")
      read_timeout = normalize_timeout(read_timeout, "read_timeout")
      byte_limit = normalize_max_bytes(max_bytes)
      current_body, body_mode = encode_body(body:, form:, multipart:)
      current_headers = request_headers(headers, body_mode)
      response = nil

      loop do
        pinned_ip = public_only ? assert_public_destination!(current_url) : nil
        rewind_multipart_uploads!(current_body) if body_mode == :multipart
        response = connection(open_timeout:, read_timeout:, pinned_ip:).run_request(
          current_method, current_url, current_body, current_headers
        ) do |request|
          request.options.on_data = proc do |chunk, received_bytes, env|
            following_redirect = follow_redirects && REDIRECT_STATUSES.include?(env.status)
            next if following_redirect

            if byte_limit && received_bytes > byte_limit
              raise ResponseTooLargeError, "response exceeds maximum size of #{byte_limit} bytes"
            end

            on_chunk.call(chunk) unless chunk.empty?
          end
        end
        break unless follow_redirects && REDIRECT_STATUSES.include?(response.status)

        location = response.headers["location"] || response.headers["Location"]
        break if location.blank?
        raise RedirectError, "maximum redirects exceeded" unless remaining.positive?

        next_url = redirect_location(current_url, location)
        current_headers = redirect_headers(current_headers, from: current_url, to: next_url)
        current_method, current_body, current_headers =
          redirect_request(response.status, current_method, current_body, current_headers)
        current_url = next_url
        remaining -= 1
      end

      Response.new(status: response.status, headers: response.headers.to_h, body: response.body.to_s)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError => e
      raise TransportError, e.message
    rescue URI::InvalidURIError => e
      raise InvalidRequestError, e.message
    end

    private

    def connection(open_timeout:, read_timeout:, pinned_ip: nil)
      Faraday.new do |f|
        f.options.open_timeout = open_timeout
        f.options.timeout      = read_timeout
        f.request :multipart
        if pinned_ip
          f.adapter :net_http do |http|
            http.ipaddr = pinned_ip
          end
        else
          f.adapter Faraday.default_adapter
        end
      end
    end

    def assert_public_destination!(url)
      uri = URI.parse(url.to_s)
      unless %w[http https].include?(uri.scheme) && uri.hostname.present?
        raise BlockedDestinationError, "URL must use HTTP or HTTPS"
      end

      addresses = Array(PublicAddress.resolve(uri.hostname))
      if addresses.empty? || addresses.any? { |addr| !PublicAddress.public?(addr) }
        raise BlockedDestinationError, "destination is not allowed"
      end

      addresses.first
    rescue URI::InvalidURIError, Resolv::ResolvError
      raise BlockedDestinationError, "destination is not allowed"
    end

    def encode_body(body:, form:, multipart:)
      modes = { body: body, form: form, multipart: multipart }.reject { |_key, value| value.nil? }
      raise InvalidRequestError, "only one of body, form, or multipart may be provided" if modes.size > 1

      if form
        raise InvalidRequestError, "form must be a hash" unless form.is_a?(Hash)

        [URI.encode_www_form(form), :form]
      elsif multipart
        raise InvalidRequestError, "multipart must be a hash" unless multipart.is_a?(Hash)

        [multipart, :multipart]
      elsif body.nil?
        [nil, nil]
      else
        [body.is_a?(String) ? body : body.to_json, body.is_a?(Hash) ? :json : :raw]
      end
    end

    def request_headers(headers, body_mode)
      raise InvalidRequestError, "headers must be a hash" unless headers.nil? || headers.is_a?(Hash)

      normalized = (headers || {}).transform_keys(&:to_s)
      if body_mode == :multipart
        existing = normalized.keys.find { |key| key.casecmp?("content-type") }
        normalized.delete(existing) if existing
        normalized["Content-Type"] = "multipart/form-data"
      elsif !header_present?(normalized, "content-type")
        normalized["Content-Type"] = case body_mode
                                    when :form
                                       "application/x-www-form-urlencoded"
                                    when :json
                                       "application/json"
                                    end
      end
      normalized.compact
    end

    def normalize_method(method)
      normalized = method.to_s.downcase.to_sym
      raise InvalidRequestError, "unsupported method: #{method}" unless ALLOWED_METHODS.include?(normalized)

      normalized
    end

    def normalize_url(url)
      uri = URI.parse(url.to_s)
      raise InvalidRequestError, "URL must use HTTP or HTTPS" unless %w[http https].include?(uri.scheme) && uri.host.present?

      uri.to_s
    end

    def normalize_redirect_limit(value)
      limit = Integer(value, exception: false)
      raise InvalidRequestError, "max_redirects must be a non-negative integer" unless limit && limit >= 0

      limit
    end

    def normalize_timeout(value, name)
      timeout = Float(value, exception: false)
      raise InvalidRequestError, "#{name} must be positive" unless timeout&.positive?

      timeout
    end

    def normalize_max_bytes(value)
      return nil if value.nil?

      limit = Integer(value, exception: false)
      raise InvalidRequestError, "max_bytes must be a non-negative integer" unless limit && limit >= 0

      limit
    end

    def redirect_location(base_url, location)
      normalize_url(URI.join(base_url, location).to_s)
    end

    def redirect_request(status, method, body, headers)
      switch_to_get = status == 303 ? method != :head : [301, 302].include?(status) && method == :post
      return [method, body, headers] unless switch_to_get

      [:get, nil, headers.reject { |key, _| CONTENT_HEADERS.include?(key.downcase) }]
    end

    def redirect_headers(headers, from:, to:)
      return headers if same_origin?(from, to)

      headers.reject { |key, _| key.match?(SENSITIVE_REDIRECT_HEADER) }
    end

    def rewind_multipart_uploads!(value)
      case value
      when Hash
        value.each_value { |nested| rewind_multipart_uploads!(nested) }
      when Array
        value.each { |nested| rewind_multipart_uploads!(nested) }
      else
        rewind_multipart_upload!(value) if multipart_upload?(value)
      end
    end

    def multipart_upload?(value)
      value.is_a?(Faraday::Multipart::FilePart) || value.is_a?(Faraday::UploadIO)
    end

    def rewind_multipart_upload!(upload)
      upload.io.rewind
    rescue StandardError => e
      raise InvalidRequestError, "unable to rewind multipart upload: #{e.message}"
    end

    def same_origin?(left, right)
      left_uri = URI.parse(left)
      right_uri = URI.parse(right)
      [left_uri.scheme, left_uri.host, left_uri.port] == [right_uri.scheme, right_uri.host, right_uri.port]
    end

    def header_present?(headers, name)
      headers.keys.any? { |key| key.casecmp?(name) }
    end
  end
end
