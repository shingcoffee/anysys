# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class GenerateTokenGenerator < BaseGenerator
          include KeyResolution

          TOKEN_TYPES = %w[jwt signed numeric_otp].freeze
          SECRET_SOURCES = KeyResolution::SECRET_SOURCES
          ALGORITHMS = FlowchartRuntime::Jwt::ALLOWED_ALGS

          generator_metadata do
            description "Issues a JWT (jwt gem, HS256/HS384/HS512/RS256), a Rails MessageVerifier signed payload, " \
                        "or a numeric OTP and writes it to resultVar. Use verify_token to check JWT or signed " \
                        "tokens. HMAC request signatures belong on verify_signature, not here. Secrets come from " \
                        "credentials, ENV, or ctx — never an inline literal. Fails with generate_token.failed."
            category :security
            version "3.0.0"
            presentation icon: "M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z",
                          color: "indigo", single_use: false, privileged: false
          end

          config_schema do
            enum :tokenType, TOKEN_TYPES, default: "jwt",
                 description: "jwt: signed JWT from payloadVariable plus claims. signed: MessageVerifier cookie/" \
                              "link for JSON payloads (pair with verify_token signed). numeric_otp: digit code of " \
                              "tokenLength, e.g. email/SMS one-time codes."
            output :resultVar, default: "token",
                   description: "Ctx key that receives the token string. Default token."
            integer :tokenLength, min: 4, max: 12, default: 6, visible: { tokenType: "numeric_otp" },
                    description: "Digit count for numeric_otp (4-12). Default 6, e.g. 004821. Not a signed token."
            input :payloadVariable, example: "payload", visible: { tokenType: %w[jwt signed] },
                  description: "Context path of the JWT or signed payload hash, e.g. payload. Optional for JWT " \
                               "(empty becomes {}). Signed payloads must be JSON-compatible."
            literal :issuer, placeholder: true, visible: { tokenType: "jwt" },
                    description: "Value written to the JWT iss claim, e.g. auth.example.com. Verify with " \
                                 "verify_token verifyIssuer."
            literal :audience, placeholder: true, visible: { tokenType: "jwt" },
                    description: "Value written to the JWT aud claim, e.g. api.example.com. Verify with " \
                                 "verify_token verifyAudience."
            literal :subject, placeholder: true, visible: { tokenType: "jwt" },
                    description: "Value written to the JWT sub claim, e.g. user-123. Prefer this over putting " \
                                 "sub only inside payloadVariable."
            flag :includeIssuedAt, default: true, visible: { tokenType: "jwt" }, group: :advanced,
                 description: "When true (default), write iat as Time.current.to_i. Turn off only when a caller " \
                              "must omit iat."
            expression :notBefore, visible: { tokenType: "jwt" },
                       description: "Ruby expression for the nbf claim, e.g. Time.current.to_i. Leave blank to omit."
            literal :expiresIn, default: "1h", placeholder: true, example: "1h",
                    visible: { tokenType: %w[jwt signed] },
                    description: "Lifetime as seconds (3600), ISO 8601 (PT1H), or a duration such as 1h. Default " \
                                 "1h. Empty means no expiry (avoid for JWTs)."
            mapping :claims, key: :literal, value: :expression, visible: { tokenType: "jwt" },
                     description: "Extra JWT claims. Keys are identifiers; values are Ruby expressions, e.g. " \
                                  "role => ctx[:user].role. Merged over payloadVariable."
            literal :keyId, placeholder: true, visible: { tokenType: "jwt" },
                    description: "Optional JWT kid header, e.g. key-2026-01, so verifiers can pick a key."
            enum :algorithm, ALGORITHMS, default: "HS256", visible: { tokenType: "jwt" },
                 description: "JWT signing algorithm. HS256 (default), HS384, HS512 use the HMAC secret; RS256 " \
                              "needs a PEM RSA private key at secretVariable. none is not allowed."
            enum :secretSource, SECRET_SOURCES, default: "credentials",
                 visible: { tokenType: %w[jwt signed] },
                 description: "Where the signing secret is read. credentials: Rails credentials at secretVariable, " \
                              "or secret_key_base when blank. env: ENV name. ctx: ctx key. Never a literal secret."
            literal :secretVariable, placeholder: true, example: "secret",
                    visible: { tokenType: %w[jwt signed] },
                    description: "credentials: dot path such as jwt.hmac. env: ENV name such as JWT_SECRET. " \
                                 "ctx: identifier such as jwt_secret. Required for env and ctx."
            literal :purpose, default: "flowchart_token", visible: { tokenType: "signed" },
                    description: "MessageVerifier purpose string. Must match verify_token, e.g. flowchart_token " \
                                 "or password_reset. A mismatch refuses the token."
            requires :secretVariable, when: { secretSource: %w[env ctx], tokenType: %w[jwt signed] }
            validate { |cfg, errors| KeyResolution.validate_secret(cfg, errors) unless cfg["tokenType"].to_s == "numeric_otp" }
          end

          def generate_body
            case value(:tokenType).to_s
            when "signed" then signed_body
            when "numeric_otp" then otp_body
            else jwt_body
            end
          end

          private

          def jwt_body
            body(
              attempt('"generate_token.failed"', FlowchartRuntime::Jwt::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::Jwt.issue(#{jwt_args})"),
                  "true"
                ]
              end
            )
          end

          def signed_body
            body(
              attempt('"generate_token.failed"', FlowchartRuntime::Token::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::Token.sign(#{signed_args})"),
                  "true"
                ]
              end
            )
          end

          def otp_body
            length = read(:tokenLength)
            body(
              assign(:resultVar,
                     "SecureRandom.random_number(10 ** #{length}).to_s.rjust(#{length}, \"0\")")
            )
          end

          def jwt_args
            parts = [optional_input(:payloadVariable), token_secret_expression]
            algorithm = value(:algorithm).to_s
            parts << "algorithm: #{read(:algorithm)}" unless algorithm.empty? || algorithm == "HS256"
            parts << "expires_in: #{read(:expiresIn)}" if present?(:expiresIn)
            parts << "issuer: #{read(:issuer)}" if present?(:issuer)
            parts << "audience: #{read(:audience)}" if present?(:audience)
            nbf = optional_expression(:notBefore)
            parts << "not_before: #{nbf}" unless nbf == "nil"
            claims = claims_literal
            parts << "claims: #{claims}" unless claims == "{}"
            parts << "key_id: #{read(:keyId)}" if present?(:keyId)
            parts << "subject: #{read(:subject)}" if present?(:subject)
            parts << "issued_at: #{value(:includeIssuedAt) ? 'true' : 'false'}"
            parts.join(", ")
          end

          def signed_args
            parts = [optional_input(:payloadVariable), "key: #{token_secret_expression}"]
            purpose = value(:purpose).to_s
            parts << "purpose: #{read(:purpose)}" unless purpose.empty? || purpose == "flowchart_token"
            parts << "expires_in: #{read(:expiresIn)}" if present?(:expiresIn)
            parts.join(", ")
          end

          def claims_literal
            rows = Array(value(:claims))
            pairs = rows.filter_map do |row|
              next unless row.is_a?(Hash)

              key = row["key"] || row[:key]
              val = row["value"] || row[:value]
              next if key.to_s.empty? || !key.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
              next if val.to_s.strip.empty? || !safe_expression?(val.to_s)

              "#{key}: #{emit_expression(val.to_s.strip)}"
            end
            "{#{pairs.join(', ')}}"
          end

          def optional_input(name)
            raw = value(name)
            raw.to_s.strip.empty? ? "nil" : read(name)
          end

          def optional_expression(name)
            raw = value(name).to_s.strip
            raw.empty? || !safe_expression?(raw) ? "nil" : read(name)
          end

          def present?(name)
            value(name).to_s.strip.present?
          end
        end
      end
    end
  end
end
