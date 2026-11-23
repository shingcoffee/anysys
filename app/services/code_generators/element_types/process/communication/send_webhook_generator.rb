# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Communication
        class SendWebhookGenerator < BaseGenerator
          SIGNATURE_ALGORITHMS = %w[sha256 sha512 sha1].freeze
          CONTENT_TYPES = %w[application/json application/x-www-form-urlencoded].freeze
          HEADER_TOKEN_RE = /\A[A-Za-z0-9!\#$%&'*+\-.^_`|~]+\z/

          generator_metadata do
            description "POSTs a JSON or form payload to a subscriber URL, optionally HMAC-signing " \
                        "the body. Use api_call for GET/PUT/PATCH or response parsing, and " \
                        "send_chat_message for chat incoming webhooks. Reads url, payloadExpression, " \
                        "headers, optional secretExpression (HMAC via OpenSSL), hmacAlgorithm, " \
                        "signatureHeader, idempotencyKey (Idempotency-Key plus transport retry), and " \
                        "contentType. Writes resultVar (default webhook_response) from the body " \
                        "(JSON object, or {body:} when the response is not JSON) and optional " \
                        "statusVar. Fails on transport errors, blocked destinations, non-2xx when " \
                        "failOnHttpError is true, or HMAC errors when signing."
            category :communication
            version "3.2.0"
            presentation icon: "M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1",
                        color: "cyan", single_use: false, privileged: false
          end

          config_schema do
            expression :url, required: true, example: '"https://hooks.example.com/webhook"',
                       description: "Webhook URL as Ruby, e.g. \"https://hooks.example.com/orders\". Must be a public https URL."
            expression :payloadExpression, required: true, example: "ctx[:webhook_payload]",
                       description: "Ruby hash (or form pairs) that becomes the body, e.g. ctx[:webhook_payload] or { event: \"created\", id: ctx[:order_id] }."
            mapping :headers, key: :literal, value: :literal, default: [],
                    description: "Extra header name to value. Static text, or a ctx/ENV expression such as ctx[:request_id]. Content-Type is set from contentType."
            expression :secretExpression,
                       description: "HMAC signing secret as a ctx/ENV/credentials expression, e.g. ENV.fetch(\"WEBHOOK_SECRET\", nil). Blank skips signing. Never a quoted secret."
            enum :hmacAlgorithm, SIGNATURE_ALGORITHMS, default: "sha256", group: :advanced,
                 description: "HMAC digest when secretExpression is set: sha256 (default), sha512, or sha1. Ignored when not signing."
            literal :signatureHeader, default: "X-Signature", group: :advanced,
                    description: "Header that carries the HMAC, e.g. X-Signature or X-Hub-Signature-256. Default X-Signature. Ignored when not signing."
            expression :idempotencyKey,
                       description: "Value sent as Idempotency-Key. Required to retry this POST when retryOnTransportError is on. Example: ctx[:request_id]."
            enum :contentType, CONTENT_TYPES, default: "application/json",
                 description: "Body encoding: application/json (.to_json, default) or application/x-www-form-urlencoded (URI.encode_www_form)."
            flag :failOnHttpError, default: true,
                 description: "When true (default), a non-2xx response fails the step with http_status. When false, the body is still stored so a later step can branch on statusVar."
            output :resultVar, default: "webhook_response",
                   description: "ctx key for the parsed body (default webhook_response). JSON object, {} if empty, or {body:} when the remote returns non-JSON text such as ok."
            output :statusVar, default: "", group: :advanced,
                   description: "Optional ctx key that stores the HTTP status code, e.g. hook_status. Blank skips it."
            transport_retry idempotent_when: { httpMethod: %w[GET HEAD PUT DELETE OPTIONS] }, or_present: :idempotencyKey
            timeouts open: 3, read: 7
            circuit_breaker_option
            validate do |cfg, errors|
              header = cfg["signatureHeader"].to_s
              next if header.blank? || HEADER_TOKEN_RE.match?(header)

              errors.add(:signatureHeader, :invalid_identifier)
            end
          end

          def generate_body
            lines = [
              "payload = #{payload_source}",
              "headers = #{headers_source}",
              *signature_lines,
              "response = #{http_call}",
              "return false unless response",
              status_assign,
              assign(:resultVar, "FlowchartRuntime::Http.parse_json(response.body, strict: false)")
            ]
            return body(lines) unless signed?

            attempt('"send_webhook.sign_failed"', FlowchartRuntime::Crypto::Error) { lines }
          end

          private

          def signed?
            value(:secretExpression).to_s.strip.present?
          end

          def form_encoded?
            value(:contentType) == "application/x-www-form-urlencoded"
          end

          def payload_source
            source = call_expression(value(:payloadExpression).to_s.strip)
            form_encoded? ? "URI.encode_www_form(#{source})" : "#{source}.to_json"
          end

          def call_expression(source)
            result = Prism.parse(source)
            statements = result.value.statements.body
            node = statements.first if result.success? && statements.size == 1
            return source if node && (primary_node?(node) || node.is_a?(Prism::HashNode))

            "(#{source})"
          end

          def headers_source
            pairs = mapping_pairs(:headers)
            pairs.unshift(["Content-Type", literal(value(:contentType))])
            if value(:idempotencyKey).to_s.strip.present?
              pairs << ["Idempotency-Key", read(:idempotencyKey)]
            end
            "{#{pairs.map { |key, source| "#{literal(key)} => #{source}" }.join(', ')}}"
          end

          def mapping_pairs(field)
            Array(value(field)).filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              val = row.key?("value") ? row["value"] : row[:value]
              next if key.to_s.strip.empty?

              [key.to_s, mapping_value_source(val)]
            end
          end

          def mapping_value_source(val)
            str = val.to_s
            stripped = str.strip
            return emit_expression(stripped) if dynamic_ruby?(stripped)

            literal(str)
          end

          def dynamic_ruby?(str)
            str.match?(/\A(?:ctx\[|ENV(?:\.|\[))/) && safe_single_expression?(str)
          end

          def signature_lines
            return [] unless signed?

            algorithm = value(:hmacAlgorithm)
            [
              "digest = FlowchartRuntime::Crypto.hmac(#{literal(algorithm)}, key: #{read(:secretExpression)}, data: payload)",
              "headers[#{literal(signature_header)}] = #{literal("#{algorithm}=")} + digest"
            ]
          end

          def signature_header
            name = value(:signatureHeader).to_s.strip
            HEADER_TOKEN_RE.match?(name) ? name : "X-Signature"
          end

          def http_call
            args = [
              "ctx",
              ":post",
              read(:url),
              "headers: headers",
              "body: payload",
              optional_kw("open_timeout", read(:connectTimeout), "3"),
              optional_kw("read_timeout", read(:readTimeout), "7"),
              optional_kw("retries", retries_source, "0"),
              optional_kw("breaker", breaker_source, "nil"),
              optional_kw("fail_on_http_error", read(:failOnHttpError), "true")
            ].compact
            "FlowchartRuntime::Http.request(#{args.join(', ')})"
          end

          def status_assign
            key = value(:statusVar).to_s
            return nil if key.empty? || !safe_ident?(key)

            "ctx[:#{key}] = response.status"
          end

          def retries_source
            value(:retryOnTransportError) ? read(:retryAttempts) : "0"
          end

          def breaker_source
            return "nil" unless value(:circuitBreaker)

            "{ name: #{read(:breakerName)}, threshold: #{read(:failureThreshold)}, reset_seconds: #{read(:resetTimeoutSeconds)} }"
          end

          def optional_kw(name, source, default)
            "#{name}: #{source}" unless source == default
          end
        end
      end
    end
  end
end
