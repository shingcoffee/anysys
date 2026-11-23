# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class EncryptDataGenerator < BaseGenerator
          include KeyResolution

          ENCODINGS = %w[hex base64 base64url raw].freeze

          generator_metadata do
            description "Encrypts sourceVariable with ActiveSupport::MessageEncryptor (aes-256-gcm) and writes " \
                        "the ciphertext to resultVar. Pair with decrypt_data using the same keySource, keyPath, " \
                        "encoding, and purpose. Keys come from Rails credentials, ENV, ctx, or a tenant-salted " \
                        "derived passphrase — never an inline secret. Fails with encrypt_data.failed on Cipher::Error."
            category :security
            version "3.0.0"
            presentation icon: "M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z",
                          color: "emerald", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "sensitive_data",
                  description: "Context path of the plaintext string to encrypt, e.g. sensitive_data or ssn."
            output :resultVar, default: "encrypted",
                   description: "Ctx key that receives the encoded ciphertext. Default encrypted. " \
                                "Pass this path to decrypt_data as sourceVariable."
            enum :keySource, KEY_SOURCES, default: "credentials",
                 description: "Where the 32-byte key is read. credentials: Rails credentials at keyPath, or " \
                              "secret_key_base when keyPath is blank. env: ENV[keyPath]. ctx: ctx[keyPath]. " \
                              "derived: PBKDF2 from deriveKeyFrom plus a tenant salt."
            literal :keyPath, placeholder: true, example: "primary_key",
                    visible: { keySource: %w[credentials env ctx] },
                    description: "credentials: dot path such as security.primary_key. env: ENV name such as " \
                                 "APP_ENCRYPT_KEY. ctx: identifier such as cipher_key. Required for env and ctx."
            input :deriveKeyFrom, example: "master_secret", visible: { keySource: "derived" },
                  description: "Context path of the passphrase used to derive the key, e.g. master_secret. " \
                               "Required when keySource is derived."
            literal :deriveKeySalt, placeholder: true, example: "user_data_v1",
                    visible: { keySource: "derived" },
                    description: "Extra salt mixed with customer_id as flowchart.cipher.<id>.<suffix>. " \
                                 "Example: user_data_v1. Must match decrypt_data."
            enum :encoding, ENCODINGS, default: "base64",
                 description: "How the ciphertext is stored. base64 (default) for JSON/text columns, base64url " \
                              "for URLs, hex for hex columns, raw for binary columns. Decrypt must use the same."
            literal :purpose, default: "flowchart_data", group: :advanced,
                    description: "MessageEncryptor purpose string. Encrypt and decrypt must share it, e.g. " \
                                 "flowchart_data or user_data. A mismatch refuses to decrypt."
            requires :keyPath, when: { keySource: %w[env ctx] }
            requires :deriveKeyFrom, when: { keySource: "derived" }
            validate { |cfg, errors| KeyResolution.validate(cfg, errors) }
          end

          def generate_body
            body(
              attempt('"encrypt_data.failed"', FlowchartRuntime::Cipher::Error) do
                [
                  key_resolution_line,
                  assign(:resultVar, "FlowchartRuntime::Cipher.encrypt_value(#{encrypt_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def encrypt_args
            parts = ["#{read(:sourceVariable)}.to_s", "key: cipher_key", "encoding: #{read(:encoding)}"]
            purpose = value(:purpose).to_s
            parts << "purpose: #{read(:purpose)}" unless purpose.empty? || purpose == "flowchart_data"
            parts.join(", ")
          end
        end
      end
    end
  end
end
