# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class AuthenticateGenerator < BaseGenerator
          AUTH_METHODS = %w[password token api_key session].freeze
          CREDENTIAL_SOURCES = %w[ctx params].freeze
          TOKEN_TYPES = %w[bearer basic custom].freeze
          ON_FAILURE = %w[fail flag].freeze

          generator_metadata do
            description "Verifies a password, HTTP token, API key, or the signed-in session and writes the " \
                        "principal (or compared secret) to resultVar. Use password after loading a tenant User; " \
                        "session after Load current user; token/api_key for constant-time secret compare. Use " \
                        "verify_token for JWTs or signed links, and authorize for role or record-owner checks. " \
                        "Fails with authenticate.failed unless onFailure is flag."
            category :security
            version "2.2.0"
            presentation icon: "M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z",
                          color: "blue", single_use: false, privileged: false
          end

          config_schema do
            enum :authMethod, AUTH_METHODS, default: "password",
                 description: "How to authenticate. password: Devise/has_secure_password on userVariable. " \
                              "token: strip Bearer/Basic then compare to expectedKeyVariable. api_key: compare " \
                              "the raw secret. session: the Warden principal in ctx[:authentication]. " \
                              "Not JWT; use verify_token for that."
            enum :credentialSource, CREDENTIAL_SOURCES, default: "ctx",
                 visible: { authMethod: %w[password token api_key] },
                 description: "Where the submitted secret is read. ctx: sourceVariable on the runtime hash " \
                              "(e.g. credentials). params: FlowchartRuntime::Step.dig(ctx[:params], sourceVariable), " \
                              "e.g. params key Authorization."
            input :sourceVariable, example: "credentials",
                  visible: { authMethod: %w[password token api_key] },
                  description: "Context path or params key holding the submitted password, token, or API key. " \
                               "Example: credentials or Authorization. Required for password, token, and api_key."
            output :resultVar, default: "authenticated_user",
                   description: "Ctx key written on success: the User for password/session, the stripped token " \
                                "string for token, true for api_key. Nil on failure when onFailure is flag."
            input :userVariable, default: "user", visible: { authMethod: "password" },
                  description: "Context path of the Authentication::User whose password is checked " \
                               "(has_secure_password). Example: user. Must already belong to ctx[:customer_id]."
            enum :tokenType, TOKEN_TYPES, default: "bearer", visible: { authMethod: "token" },
                 description: "Prefix stripped before constant-time compare. bearer drops 'Bearer ', " \
                              "basic drops 'Basic ', custom compares the raw string to expectedKeyVariable."
            input :expectedKeyVariable, example: "stored_key",
                  visible: { authMethod: %w[token api_key] },
                  description: "Context path of the expected secret, e.g. stored_key. Compared in constant time. " \
                               "Required for token and api_key. Never paste the secret into the flowchart."
            requires :expectedKeyVariable, when: { authMethod: %w[token api_key] }
            requires :sourceVariable, when: { authMethod: %w[password token api_key] }
            enum :onFailure, ON_FAILURE, default: "fail",
                 description: "fail: Step.fail authenticate.failed and stop. flag: write resultVar (possibly nil) " \
                              "and continue so a later decision can branch."
          end

          def generate_body
            case value(:authMethod).to_s
            when "session" then session_body
            when "token" then token_body
            when "api_key" then api_key_body
            else password_body
            end
          end

          private

          def password_body
            auth_body(
              "FlowchartRuntime::Authentication.password(user: #{read(:userVariable)}, " \
              "password: #{credential_expr}, customer_id: ctx[:customer_id])",
              field: :sourceVariable
            )
          end

          def session_body
            auth_body(
              "FlowchartRuntime::Authentication.session(context: ctx[:authentication], " \
              "customer_id: ctx[:customer_id])"
            )
          end

          def token_body
            args = ["raw: #{credential_expr}", "expected: #{read(:expectedKeyVariable)}"]
            token_type = value(:tokenType).to_s
            args << "type: #{read(:tokenType)}" unless token_type.empty? || token_type == "bearer"
            auth_body(
              "FlowchartRuntime::Authentication.token(#{args.join(', ')})",
              field: :expectedKeyVariable
            )
          end

          def api_key_body
            auth_body(
              "FlowchartRuntime::Authentication.api_key(raw: #{credential_expr}, " \
              "expected: #{read(:expectedKeyVariable)})",
              field: :expectedKeyVariable
            )
          end

          def auth_body(call, field: nil)
            lines = [
              "authenticated = #{call}",
              assign(:resultVar, "authenticated")
            ]
            lines.concat(denial_lines(field: field))
            lines << "true"
            body(lines)
          end

          def denial_lines(field: nil)
            return [] if value(:onFailure).to_s == "flag"

            [
              "unless authenticated",
              "  #{fail_with('"authenticate.failed"', field: field)}",
              "end"
            ]
          end

          def credential_expr
            key = value(:sourceVariable).to_s
            case value(:credentialSource).to_s
            when "params"
              ident = safe_ident?(key) ? key : "credentials"
              "FlowchartRuntime::Step.dig(ctx[:params], :#{ident})"
            else
              read(:sourceVariable)
            end
          end
        end
      end
    end
  end
end
