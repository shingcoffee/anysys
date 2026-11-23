# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Communication
        class ApiCallGenerator < BaseGenerator
          HTTP_METHODS = %w[GET HEAD POST PUT PATCH DELETE OPTIONS].freeze
          AUTH_TYPES = %w[none bearer basic apiKey].freeze
          RESPONSE_FORMATS = %w[json text binary].freeze
          BODY_FORMATS = %w[json form text xml binary].freeze
          BODY_METHODS = %w[POST PUT PATCH].freeze
          CONTENT_TYPE_BY_FORMAT = {
            "json" => "application/json",
            "form" => "application/x-www-form-urlencoded",
            "text" => "text/plain",
            "xml" => "application/xml",
            "binary" => "application/octet-stream"
          }.freeze

          generator_metadata do
            description "Calls an external HTTP API and stores the response. Use send_webhook " \
                        "for a signed POST to a subscriber URL, or send_chat_message for Slack/" \
                        "Teams/DingTalk/WeCom/Feishu incoming webhooks. Reads url, optional " \
                        "queryParams, headers, bodyTemplate (POST/PUT/PATCH), and authType " \
                        "credentials from ctx/ENV expressions (never paste secrets). Writes " \
                        "resultVar (default api_response): parsed JSON, text, or raw bytes. " \
                        "Optionally writes statusVar and headersVar. Fails on blocked " \
                        "destinations, transport errors, non-2xx when failOnHttpError is true, " \
                        "or invalid JSON when responseFormat is json."
            category :communication
            version "3.2.0"
            presentation icon: "M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
                        color: "amber", single_use: false, privileged: false
          end

          config_schema do
            enum :httpMethod, HTTP_METHODS, default: "GET",
                 description: "HTTP verb. GET/HEAD/OPTIONS send no body. POST/PUT/PATCH send " \
                              "bodyTemplate encoded as bodyFormat. DELETE has no body. Default GET."
            expression :url, required: true, example: '"https://api.example.com/users"',
                       description: "Request URL as Ruby, e.g. \"https://api.example.com/orders\" " \
                                    "or ctx[:endpoint]. Must be a public https URL; private hosts are blocked."
            mapping :headers, key: :literal, value: :literal, default: [],
                    description: "Extra header name to value. Static text, or a ctx/ENV expression " \
                                 "such as ctx[:request_id]. Authorization is set by authType, not here."
            mapping :queryParams, key: :literal, value: :literal, default: [],
                    description: "Query string keys appended to the URL. Values are static text or a " \
                                 "ctx/ENV expression such as ctx[:order_id]."
            expression :bodyTemplate, visible: { httpMethod: BODY_METHODS },
                       description: "Ruby expression for the POST/PUT/PATCH body, e.g. ctx[:payload] " \
                                    "or { id: ctx[:order_id] }. Hidden for GET/HEAD/DELETE/OPTIONS."
            enum :bodyFormat, BODY_FORMATS, default: "json", visible: { httpMethod: BODY_METHODS },
                 description: "How bodyTemplate is encoded: json (.to_json), form (form:), text/xml/" \
                              "binary (raw string). Sets Content-Type except form. Default json."
            enum :authType, AUTH_TYPES, default: "none",
                 description: "none sends no credentials. bearer sets Authorization: Bearer <authToken>. " \
                              "basic sets Basic auth from authUsername/authPassword. apiKey sets apiKeyHeader."
            expression :authToken, visible: { authType: %w[bearer apiKey] },
                       description: "Bearer token or API key as a ctx/ENV/credentials expression, " \
                                    "e.g. ENV.fetch(\"API_TOKEN\", nil). Never a quoted secret string."
            expression :authUsername, visible: { authType: "basic" },
                       description: "Basic-auth username expression, e.g. ENV.fetch(\"API_USER\", nil)."
            expression :authPassword, visible: { authType: "basic" },
                       description: "Basic-auth password expression, e.g. ENV.fetch(\"API_PASSWORD\", nil). " \
                                    "Never a quoted secret string."
            literal :apiKeyHeader, default: "X-API-Key", visible: { authType: "apiKey" },
                    description: "Header that carries the API key when authType is apiKey. Default X-API-Key."
            enum :responseFormat, RESPONSE_FORMATS, default: "json",
                 description: "How the body is stored in resultVar: json (parsed object, {} if empty), " \
                              "text (string), or binary (raw bytes). Default json. Invalid JSON fails the step."
            literal :responseParseKey,
                    description: "Optional dotted JSON path kept from the parsed object, e.g. data.user. " \
                                 "Blank stores the whole object. Ignored unless responseFormat is json."
            flag :followRedirects, default: true,
                 description: "Follow HTTP redirects up to maxRedirects hops. Default true."
            integer :maxRedirects, min: 0, max: 20, default: 5, visible: { followRedirects: true },
                    description: "Maximum redirect hops when followRedirects is true (0-20). Default 5."
            flag :failOnHttpError, default: true,
                 description: "When true (default), a non-2xx response fails the step with http_status. " \
                              "When false, the body is still stored so a later step can branch on statusVar."
            expression :idempotencyKey,
                       description: "Value sent as Idempotency-Key. Also allows transport retry on POST/PATCH " \
                                    "when retryOnTransportError is on. Example: ctx[:request_id]."
            output :resultVar, default: "api_response",
                   description: "ctx key for the parsed body (default api_response). Later steps read this hash, string, or bytes."
            output :statusVar, default: "", group: :advanced,
                   description: "Optional ctx key that stores the HTTP status code, e.g. http_status. Blank skips it."
            output :headersVar, default: "", group: :advanced,
                   description: "Optional ctx key that stores response headers, e.g. http_headers. Blank skips it."
            requires :authToken, when: { authType: %w[bearer apiKey] }
            requires :authUsername, when: { authType: "basic" }
            requires :authPassword, when: { authType: "basic" }
            transport_retry idempotent_when: { httpMethod: %w[GET HEAD PUT DELETE OPTIONS] }, or_present: :idempotencyKey
            timeouts open: 3, read: 7
            circuit_breaker_option
          end

          def generate_body
            lines = [
              "response = #{http_call}",
              "return false unless response",
              status_assign,
              headers_assign
            ]
            if value(:responseFormat) == "json"
              lines << attempt(:invalid_json, JSON::ParserError) { parse_lines }
            else
              lines.concat(parse_lines)
            end
            body(lines)
          end

          private

          def http_call
            method = value(:httpMethod).to_s.downcase.to_sym
            args = [
              "ctx",
              literal(method),
              read(:url),
              ("headers: #{headers_source}" unless headers_source == "{}"),
              ("query: #{query_source}" unless query_pairs.empty?),
              body_kw,
              optional_kw("open_timeout", read(:connectTimeout), "3"),
              optional_kw("read_timeout", read(:readTimeout), "7"),
              optional_kw("retries", retries_source, "0"),
              optional_kw("breaker", breaker_source, "nil"),
              ("follow_redirects: true" if value(:followRedirects)),
              (optional_kw("max_redirects", read(:maxRedirects), "3") if value(:followRedirects)),
              optional_kw("fail_on_http_error", read(:failOnHttpError), "true")
            ].compact
            "FlowchartRuntime::Http.request(#{args.join(', ')})"
          end

          def body_kw
            return nil unless BODY_METHODS.include?(value(:httpMethod).to_s)
            return nil if value(:bodyTemplate).to_s.strip.empty?

            source = call_expression(value(:bodyTemplate).to_s.strip)
            case value(:bodyFormat)
            when "form" then "form: #{source}"
            when "text", "xml", "binary" then "body: #{source}.to_s"
            else "body: #{source}.to_json"
            end
          end

          def call_expression(source)
            result = Prism.parse(source)
            statements = result.value.statements.body
            node = statements.first if result.success? && statements.size == 1
            return source if node && (primary_node?(node) || node.is_a?(Prism::HashNode))

            "(#{source})"
          end

          def headers_source
            @headers_source ||= begin
              pairs = mapping_pairs(:headers)
              content_type = CONTENT_TYPE_BY_FORMAT[value(:bodyFormat).to_s]
              if BODY_METHODS.include?(value(:httpMethod).to_s) && content_type && value(:bodyFormat) != "form"
                pairs.unshift(["Content-Type", literal(content_type)])
              end
              case value(:authType)
              when "bearer"
                pairs << ["Authorization", %{"Bearer " + #{read(:authToken)}.to_s}]
              when "basic"
                pairs << [
                  "Authorization",
                  %{"Basic " + Base64.strict_encode64(#{read(:authUsername)}.to_s + ":" + #{read(:authPassword)}.to_s)}
                ]
              when "apiKey"
                header = value(:apiKeyHeader).to_s.strip
                header = "X-API-Key" if header.empty?
                pairs << [header, "#{read(:authToken)}.to_s"]
              end
              if value(:idempotencyKey).to_s.strip.present?
                pairs << ["Idempotency-Key", read(:idempotencyKey)]
              end
              hash_source(pairs)
            end
          end

          def query_source
            hash_source(query_pairs)
          end

          def query_pairs
            mapping_pairs(:queryParams)
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

          def hash_source(pairs)
            return "{}" if pairs.empty?

            "{#{pairs.map { |key, source| "#{literal(key)} => #{source}" }.join(', ')}}"
          end

          def retries_source
            value(:retryOnTransportError) ? read(:retryAttempts) : "0"
          end

          def breaker_source
            return "nil" unless value(:circuitBreaker)

            "{ name: #{read(:breakerName)}, threshold: #{read(:failureThreshold)}, reset_seconds: #{read(:resetTimeoutSeconds)} }"
          end

          def status_assign
            key = value(:statusVar).to_s
            return nil if key.empty? || !safe_ident?(key)

            "ctx[:#{key}] = response.status"
          end

          def headers_assign
            key = value(:headersVar).to_s
            return nil if key.empty? || !safe_ident?(key)

            "ctx[:#{key}] = response.headers"
          end

          def parse_lines
            case value(:responseFormat)
            when "text"
              [assign(:resultVar, "response.body.to_s")]
            when "binary"
              [assign(:resultVar, "response.body")]
            else
              json_lines
            end
          end

          def json_lines
            parse = "FlowchartRuntime::Http.parse_json(body)"
            lines = ["body = response.body.to_s"]
            keys = dig_keys
            if keys
              lines << "parsed = #{parse}"
              lines << assign(:resultVar, "FlowchartRuntime::Step.dig(parsed, #{keys})")
            else
              lines << assign(:resultVar, parse)
            end
            lines
          end

          def dig_keys
            path = value(:responseParseKey).to_s.strip
            return nil if path.empty?

            segments = path.split(".").reject(&:empty?)
            return nil unless segments.all? { |segment| safe_ident?(segment) }

            segments.map { |segment| ":#{segment}" }.join(", ")
          end

          def optional_kw(name, source, default)
            "#{name}: #{source}" unless source == default
          end
        end
      end
    end
  end
end
