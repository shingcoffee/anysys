# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class VerifySignatureGenerator < BaseGenerator
          SECRET_SOURCES = %w[credentials env ctx].freeze
          ALGORITHMS = FlowchartRuntime::Signature::DIGESTS
          ENCODINGS = FlowchartRuntime::Signature::ENCODINGS
          SIGNED_PAYLOADS = FlowchartRuntime::Signature::SIGNED_PAYLOADS
          ON_INVALID = %w[fail flag].freeze
          ENV_NAME_RE = KeyResolution::ENV_NAME_RE
          CREDENTIAL_SEGMENT_RE = KeyResolution::CREDENTIAL_SEGMENT_RE

          generator_metadata do
            description "Verifies an inbound webhook HMAC (constant-time via " \
                        "ActiveSupport::SecurityUtils) with optional timestamp replay protection. " \
                        "Use this before trusting a callback body; use send_webhook to sign " \
                        "outbound POSTs. Reads payloadVariable, signatureVariable, and the secret " \
                        "from credentials (keyPath), ENV (keyPath), or ctx (secretVariable)—never " \
                        "a literal secret. signedPayload timestamp_body also reads " \
                        "timestampVariable, payloadSeparator, and toleranceSeconds (default 300). " \
                        "Writes resultVar (default signature_valid). onInvalid fail (default) " \
                        "refuses with verify_signature.invalid, expired, or missing_secret; flag " \
                        "stores false and continues."
            category :security
            version "1.1.0"
            presentation icon: "M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
                          color: "rose", single_use: false, privileged: false
          end

          config_schema do
            input :payloadVariable, required: true, example: "raw_body",
                  description: "ctx path of the raw request body that was signed, e.g. raw_body. Must be the exact bytes the sender hashed."
            input :signatureVariable, required: true, example: "params.signature",
                  description: "ctx path of the signature header or query value, e.g. params.signature or params[\"X-Hub-Signature-256\"]."
            enum :secretSource, SECRET_SOURCES, default: "credentials",
                 description: "Where the HMAC secret is read: credentials (Rails credentials at keyPath), env (ENV[keyPath]), or ctx (secretVariable). Never a literal secret."
            literal :keyPath, placeholder: true, example: "webhook_secret",
                    visible: { secretSource: %w[credentials env] },
                    description: "credentials: dot-path such as webhooks.signing_secret. env: ENV name such as WEBHOOK_SECRET. Required for credentials and env."
            input :secretVariable, example: "webhook_secret", visible: { secretSource: "ctx" },
                  description: "ctx path of the HMAC secret when secretSource is ctx, e.g. webhook_secret. Hidden for credentials/env."
            enum :algorithm, ALGORITHMS, default: "sha256",
                 description: "HMAC digest used to recompute the signature: sha256 (default), sha512, or sha1. Must match the sender."
            enum :encoding, ENCODINGS, default: "hex", group: :advanced,
                 description: "How the digest is encoded before comparison: hex (default) or base64. Comparison is constant-time."
            literal :signaturePrefix, default: "", placeholder: true, group: :advanced,
                    description: "Prefix stripped from the header before comparison, e.g. sha256=. Blank keeps the raw header. Stripe v1= candidates are also accepted."
            enum :signedPayload, SIGNED_PAYLOADS, default: "body",
                 description: "body (default) HMACs the payload only. timestamp_body HMACs timestamp + separator + payload and applies toleranceSeconds."
            input :timestampVariable, example: "params.timestamp", visible: { signedPayload: "timestamp_body" },
                  description: "ctx path of the timestamp included in the signed payload, e.g. params.timestamp. Unix seconds or milliseconds."
            literal :payloadSeparator, default: ".", visible: { signedPayload: "timestamp_body" }, group: :advanced,
                    description: "String inserted between timestamp and body when both are signed. Default \".\" (Stripe-style t.payload)."
            integer :toleranceSeconds, min: 0, max: 86_400, default: 300,
                    visible: { signedPayload: "timestamp_body" }, group: :advanced,
                    description: "Maximum age of the timestamp in seconds (0-86400). Default 300. 0 disables the replay check."
            enum :onInvalid, ON_INVALID, default: "fail",
                 description: "fail (default) refuses the submission with verify_signature.invalid or expired. flag stores false in resultVar and continues."
            output :resultVar, default: "signature_valid",
                   description: "ctx key for the boolean result (default signature_valid). true when the HMAC matches; false when onInvalid is flag and it does not."
            requires :keyPath, when: { secretSource: %w[credentials env] }
            requires :secretVariable, when: { secretSource: "ctx" }
            requires :timestampVariable, when: { signedPayload: "timestamp_body" }
            validate do |cfg, errors|
              source = cfg["secretSource"].presence || "credentials"
              path = cfg["keyPath"].to_s.strip
              next if path.empty? || source.to_s == "ctx"

              case source.to_s
              when "env"
                errors.add(:keyPath, :invalid_env_name, value: path) unless ENV_NAME_RE.match?(path)
              when "credentials"
                bad = path.split(".").map(&:strip).reject(&:empty?)
                           .reject { |segment| CREDENTIAL_SEGMENT_RE.match?(segment) }
                errors.add(:keyPath, :invalid_credential_path, value: bad.join(", ")) if bad.any?
              end
            end
          end

          def generate_body
            lines = [assign(:resultVar, "FlowchartRuntime::Signature.verify(#{verify_args})")]
            lines << "true" if value(:onInvalid).to_s == "flag"
            body(lines)
          end

          private

          def verify_args
            parts = [
              "ctx",
              "payload: #{read(:payloadVariable)}",
              "signature: #{read(:signatureVariable)}",
              "secret: #{secret_expr}"
            ]
            algorithm = value(:algorithm).to_s
            parts << "algorithm: #{read(:algorithm)}" unless algorithm.empty? || algorithm == "sha256"
            encoding = value(:encoding).to_s
            parts << "encoding: #{read(:encoding)}" unless encoding.empty? || encoding == "hex"
            parts << "prefix: #{read(:signaturePrefix)}" unless value(:signaturePrefix).to_s.empty?
            timestamp_body = value(:signedPayload).to_s == "timestamp_body"
            parts << "signed_payload: #{read(:signedPayload)}" if timestamp_body
            if timestamp_body
              parts << "timestamp: #{read(:timestampVariable)}"
              separator = value(:payloadSeparator).to_s
              parts << "separator: #{read(:payloadSeparator)}" unless separator.empty? || separator == "."
              parts << "tolerance: #{read(:toleranceSeconds)}" unless value(:toleranceSeconds).to_i == 300
            end
            parts << "on_invalid: #{read(:onInvalid)}" unless value(:onInvalid).to_s == "fail"
            parts.join(", ")
          end

          def secret_expr
            case value(:secretSource).to_s
            when "env" then env_secret_expression
            when "ctx" then read(:secretVariable)
            else credentials_secret_expression
            end
          end

          def env_secret_expression
            name = value(:keyPath).to_s.strip
            return "nil" unless ENV_NAME_RE.match?(name)

            "ENV.fetch(#{name.inspect}, nil)"
          end

          def credentials_secret_expression
            segments = value(:keyPath).to_s.split(".").map(&:strip).reject(&:empty?)
            return "nil" unless segments.any? && segments.all? { |segment| CREDENTIAL_SEGMENT_RE.match?(segment) }

            "Rails.application.credentials.dig(#{safe_symbols(segments)})"
          end
        end
      end
    end
  end
end
