# frozen_string_literal: true

require "json"

module FlowchartRuntime
  module Http
    class Error < StandardError; end

    DEFAULT_OPEN_TIMEOUT = 3
    DEFAULT_READ_TIMEOUT = 7
    MAX_EXTRA_ATTEMPTS = 2

    module_function

    # Empty body -> {}; JSON -> Hash; non-JSON raises when strict, else { body: text }.
    def parse_json(body, symbolize_names: true, strict: true)
      text = body.to_s
      return {} if text.strip.empty?

      JSON.parse(text, symbolize_names: symbolize_names)
    rescue JSON::ParserError
      raise if strict

      symbolize_names ? { body: text } : { "body" => text }
    end

    def request(ctx, method, url, headers: {}, query: {}, body: nil, form: nil,
                open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
                retries: 0, breaker: nil, follow_redirects: false, max_redirects: 3,
                max_bytes: nil, public_only: true, fail_on_http_error: true)
      raise Error, "url is required" if url.to_s.strip.empty?

      extra_attempts = [Integer(retries, exception: false) || 0, MAX_EXTRA_ATTEMPTS].min
      extra_attempts = 0 if extra_attempts.negative?
      target = apply_query(url, query)
      gate = breaker_options(ctx, breaker)
      return Step.fail(ctx, :circuit_open, name: gate[:name]) if gate && !admit_breaker?(gate)

      attempt = 0
      transport_error = nil
      loop do
        remaining = RunContext.remaining.to_f
        if remaining < 1
          return Step.fail(ctx, :timed_out) if attempt.zero?

          return Step.fail(ctx, :transport_error, reason: transport_error.class.name.demodulize)
        end

        response = fetch(
          method,
          target,
          max_bytes: max_bytes,
          headers: headers,
          body: body,
          form: form,
          open_timeout: [open_timeout.to_f, remaining].min,
          read_timeout: [read_timeout.to_f, remaining].min,
          follow_redirects: follow_redirects,
          max_redirects: max_redirects,
          public_only: public_only
        )
        return finish_status(ctx, response, gate, fail_on_http_error: fail_on_http_error)
      rescue OutboundHttp::BlockedDestinationError
        return Step.fail(ctx, :blocked_destination)
      rescue OutboundHttp::TransportError => error
        transport_error = error
        record_breaker(gate, :failure)
        attempt += 1
        next if attempt <= extra_attempts && RunContext.remaining.to_f >= 1

        return Step.fail(ctx, :transport_error, reason: error.class.name.demodulize)
      rescue OutboundHttp::ResponseTooLargeError => error
        record_breaker(gate, :failure)
        return Step.fail(ctx, :transport_error, reason: error.class.name.demodulize)
      rescue OutboundHttp::InvalidRequestError, OutboundHttp::RedirectError => error
        return Step.fail(ctx, :transport_error, reason: error.class.name.demodulize)
      end
    end

    # A size cap streams the body so an oversized response aborts mid-transfer
    # instead of being buffered whole first.
    def fetch(method, url, max_bytes:, **options)
      return OutboundHttp.request(method, url, **options) if max_bytes.nil?

      buffer = String.new(encoding: Encoding::BINARY)
      streamed = OutboundHttp.stream(method, url, max_bytes: max_bytes, **options) { |chunk| buffer << chunk }
      OutboundHttp::Response.new(status: streamed.status, headers: streamed.headers, body: buffer)
    end

    def apply_query(url, query)
      params = query.to_h
      return url if params.empty?

      uri = URI.parse(url.to_s)
      extra = URI.encode_www_form(params)
      uri.query = [uri.query, extra].compact.reject(&:empty?).join("&")
      uri.to_s
    rescue URI::InvalidURIError
      raise Error, "url is required"
    end

    def breaker_options(ctx, breaker)
      return nil if breaker.blank?

      name = breaker[:name] || breaker["name"]
      raise Error, "breaker name is required" if name.to_s.strip.empty?

      {
        customer_id: ctx[:customer_id],
        name: name,
        threshold: breaker[:threshold] || breaker["threshold"] || 5,
        reset_seconds: breaker[:reset_seconds] || breaker["reset_seconds"] || 60
      }
    end

    def admit_breaker?(gate)
      CircuitBreaker.evaluate(
        gate[:customer_id],
        gate[:name],
        outcome: "none",
        failure_threshold: gate[:threshold],
        reset_timeout: gate[:reset_seconds]
      )[:allowed]
    end

    def record_breaker(gate, outcome)
      return unless gate

      CircuitBreaker.evaluate(
        gate[:customer_id],
        gate[:name],
        outcome: outcome.to_s,
        failure_threshold: gate[:threshold],
        reset_timeout: gate[:reset_seconds]
      )
    end

    def finish_status(ctx, response, gate, fail_on_http_error: true)
      if response.success?
        record_breaker(gate, :success)
        return response
      end

      record_breaker(gate, :failure) if response.status >= 500
      return response if fail_on_http_error == false

      Step.fail(ctx, :http_status, status: response.status)
    end

    private_class_method :fetch, :apply_query, :breaker_options, :admit_breaker?, :record_breaker, :finish_status
  end
end
