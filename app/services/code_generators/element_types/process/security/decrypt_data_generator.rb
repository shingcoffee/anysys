# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class DecryptDataGenerator < BaseGenerator
          include KeyResolution

          ENCODINGS = %w[hex base64 base64url raw].freeze

          generator_metadata do
            description "Decrypts sourceVariable ciphertext produced by encrypt_data (aes-256-gcm MessageEncryptor) " \
                        "and writes plaintext to resultVar. keySource, keyPath, encoding, and purpose must match " \
                        "the encrypt step. Keys come from credentials, ENV, ctx, or a tenant-salted derived " \
                        "passphrase. Fails with decrypt_data.failed on a wrong key, purpose, or encoding."
            category :security
            version "3.0.0"
            presentation icon: "M8 11V7a4 4 0 118 0m-4 8v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2z",
                          color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "encrypted",
                  description: "Context path of the ciphertext string, e.g. encrypted. Same encoding as encrypt_data."
            output :resultVar, default: "decrypted",
                   description: "Ctx key that receives the plaintext string. Default decrypted."
            enum :keySource, KEY_SOURCES, default: "credentials",
                 description: "Where the key is read. Must match encrypt_data: credentials (keyPath or " \
                              "secret_key_base), env, ctx, or derived from deriveKeyFrom plus the tenant salt."
            literal :keyPath, placeholder: true, example: "primary_key",
                    visible: { keySource: %w[credentials env ctx] },
                    description: "credentials: dot path such as security.primary_key. env: ENV name such as " \
                                 "APP_DECRYPT_KEY. ctx: identifier such as cipher_key. Required for env and ctx."
            input :deriveKeyFrom, example: "master_secret", visible: { keySource: "derived" },
                  description: "Context path of the passphrase used to derive the key, e.g. master_secret. " \
                               "Required when keySource is derived."
            literal :deriveKeySalt, placeholder: true, example: "user_data_v1",
                    visible: { keySource: "derived" },
                    description: "Extra salt mixed with customer_id as flowchart.cipher.<id>.<suffix>. " \
                                 "Example: user_data_v1. Must match encrypt_data."
            enum :encoding, ENCODINGS, default: "base64",
                 description: "How the stored ciphertext is encoded. Must match encrypt_data: base64 (default), " \
                              "base64url, hex, or raw."
            literal :purpose, default: "flowchart_data", group: :advanced,
                    description: "MessageEncryptor purpose string. Must match encrypt_data, e.g. flowchart_data " \
                                 "or user_data. A mismatch fails the step."
            requires :keyPath, when: { keySource: %w[env ctx] }
            requires :deriveKeyFrom, when: { keySource: "derived" }
            validate { |cfg, errors| KeyResolution.validate(cfg, errors) }
          end

          def generate_body
            body(
              attempt('"decrypt_data.failed"', FlowchartRuntime::Cipher::Error) do
                [
                  key_resolution_line,
                  assign(:resultVar, "FlowchartRuntime::Cipher.decrypt_value(#{decrypt_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def decrypt_args
            parts = [read(:sourceVariable), "key: cipher_key", "encoding: #{read(:encoding)}"]
            purpose = value(:purpose).to_s
            parts << "purpose: #{read(:purpose)}" unless purpose.empty? || purpose == "flowchart_data"
            parts.join(", ")
          end
        end
      end
    end
  end
end
