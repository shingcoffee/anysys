# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class VerifyTokenGenerator < BaseGenerator
          include KeyResolution

          TOKEN_TYPES = %w[jwt signed].freeze
          SECRET_SOURCES = KeyResolution::SECRET_SOURCES
          ALGORITHMS = FlowchartRuntime::Jwt::ALLOWED_ALGS
          ON_INVALID = %w[fail flag].freeze

          generator_metadata do
            description "Verifies a JWT (jwt gem, allow-listed HS*/RS256) or a Rails MessageVerifier signed " \
                        "payload from generate_token and writes claims to resultVar. Secrets come from credentials, " \
                        "ENV, or ctx — never an inline literal. Use authenticate for passwords/sessions and " \
                        "verify_signature for inbound HMAC webhooks. Invalid tokens fail with verify_token.failed " \
                        "unless onInvalid is flag (then validVar is boolean)."
            category :security
            version "3.0.0"
            presentation icon: "M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z",
                          color: "teal", single_use: false, privileged: false
          end

          config_schema do
            enum :tokenType, TOKEN_TYPES, default: "jwt",
                 description: "jwt: decode and verify a JWT from generate_token jwt. signed: verify a " \
                              "MessageVerifier payload from generate_token signed (same purpose)."
            input :sourceVariable, required: true, example: "token",
                  description: "Context path of the token string, e.g. token or auth_token."
            enum :secretSource, SECRET_SOURCES, default: "credentials",
                 description: "Where the verification secret is read. Must match generate_token: credentials " \
                              "(secretVariable or secret_key_base), env, or ctx. Never a literal secret."
            literal :secretVariable, placeholder: true, example: "secret",
                    description: "credentials: dot path such as jwt.hmac. env: ENV name such as JWT_SECRET. " \
                                 "ctx: identifier such as jwt_secret. Required for env and ctx. Blank credentials uses secret_key_base."
            enum :algorithm, ALGORITHMS, default: "HS256", visible: { tokenType: "jwt" },
                 description: "Single allowed JWT algorithm. HS256 (default), HS384, HS512, or RS256. " \
                              "Must match the issuer. none is not allowed."
            literal :verifyIssuer, placeholder: true, visible: { tokenType: "jwt" },
                    description: "Expected JWT iss claim, e.g. https://issuer.example. Leave blank to skip iss."
            literal :verifyAudience, placeholder: true, visible: { tokenType: "jwt" },
                    description: "Expected JWT aud claim, e.g. api.example. Leave blank to skip aud."
            integer :leewaySeconds, min: 0, default: 0, visible: { tokenType: "jwt" },
                    description: "Clock-skew leeway in seconds for exp/nbf/iat. Default 0. Example: 10."
            mapping :requiredClaims, key: :literal, value: :literal, visible: { tokenType: "jwt" },
                     description: "Claim paths that must be present. Nested keys use dots, e.g. user.role => " \
                                  "admin. A blank value only checks presence."
            literal :purpose, default: "flowchart_token", visible: { tokenType: "signed" },
                    description: "MessageVerifier purpose. Must match generate_token, e.g. flowchart_token " \
                                 "or password_reset."
            output :resultVar, default: "claims",
                   description: "Ctx key that receives the JWT payload hash or the signed JSON payload. " \
                                "Default claims. Nil when onInvalid is flag and the token is invalid."
            enum :onInvalid, ON_INVALID, default: "fail",
                 description: "fail: stop with verify_token.failed. flag: write resultVar (possibly nil) and " \
                              "validVar, then continue."
            output :validVar, default: "token_valid", visible: { onInvalid: "flag" },
                   description: "Ctx key set to true or false when onInvalid is flag. Default token_valid."
            validate { |cfg, errors| KeyResolution.validate_secret(cfg, errors) }
          end

          def generate_body
            if value(:tokenType).to_s == "signed"
              signed_body
            else
              jwt_body
            end
          end

          private

          def jwt_body
            if value(:onInvalid).to_s == "flag"
              body(
                attempt('"verify_token.failed"', FlowchartRuntime::Jwt::Error) do
                  [
                    "claims = FlowchartRuntime::Jwt.verify_or_nil(#{jwt_args})",
                    assign(:resultVar, "claims"),
                    assign(:validVar, "!claims.nil?"),
                    "true"
                  ]
                end
              )
            else
              body(
                attempt('"verify_token.failed"', FlowchartRuntime::Jwt::Error) do
                  [
                    assign(:resultVar, "FlowchartRuntime::Jwt.verify(#{jwt_args})"),
                    "true"
                  ]
                end
              )
            end
          end

          def signed_body
            if value(:onInvalid).to_s == "flag"
              body(
                attempt('"verify_token.failed"', FlowchartRuntime::Token::Error) do
                  [
                    "claims = FlowchartRuntime::Token.verify_or_nil(#{signed_args})",
                    assign(:resultVar, "claims"),
                    assign(:validVar, "!claims.nil?"),
                    "true"
                  ]
                end
              )
            else
              body(
                attempt('"verify_token.failed"', FlowchartRuntime::Token::Error) do
                  [
                    assign(:resultVar, "FlowchartRuntime::Token.verify(#{signed_args})"),
                    "true"
                  ]
                end
              )
            end
          end

          def jwt_args
            parts = [read(:sourceVariable), token_secret_expression, "algorithms: #{algorithms_literal}"]
            parts << "iss: #{read(:verifyIssuer)}" if present?(:verifyIssuer)
            parts << "aud: #{read(:verifyAudience)}" if present?(:verifyAudience)
            parts << "leeway: #{read(:leewaySeconds)}" unless value(:leewaySeconds).to_i.zero?
            claims = claims_literal
            parts << "required_claims: #{claims}" unless claims == "{}"
            parts.join(", ")
          end

          def signed_args
            parts = [read(:sourceVariable), "key: #{token_secret_expression}"]
            purpose = value(:purpose).to_s
            parts << "purpose: #{read(:purpose)}" unless purpose.empty? || purpose == "flowchart_token"
            parts.join(", ")
          end

          def algorithms_literal
            literal([value(:algorithm).to_s.presence || "HS256"].select { |item| ALGORITHMS.include?(item) }.presence || ["HS256"])
          end

          def claims_literal
            rows = Array(value(:requiredClaims))
            pairs = rows.filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              val = row["value"] || row[:value]
              next if key.to_s.empty?

              "#{key.to_s.inspect} => #{literal(val)}"
            end
            "{#{pairs.join(', ')}}"
          end

          def present?(name)
            value(name).to_s.strip.present?
          end
        end
      end
    end
  end
end
