# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        class HashDataGenerator < BaseGenerator
          ALGORITHMS = %w[bcrypt scrypt argon2 pbkdf2 sha256 sha512].freeze
          ENCODINGS = FlowchartRuntime::Crypto::HASH_ENCODINGS
          DIGEST_ALGORITHMS = FlowchartRuntime::Crypto::HASH_ALGORITHMS
          PASSWORD_ALGORITHMS = FlowchartRuntime::PasswordHash::PASSWORD_ALGORITHMS
          MAX_ITERATIONS = FlowchartRuntime::Crypto::MAX_ITERATIONS

          generator_metadata do
            description "Hashes sourceVariable into resultVar. Use bcrypt (default cost 12), scrypt, or argon2 " \
                        "to store passwords — never sha256/sha512 for passwords. Use sha256/sha512 (optional salt " \
                        "and pepper) for checksums, and pbkdf2 when a caller requires that KDF. MD5 and SHA-1 are " \
                        "not offered. Fails with hash_data.failed on Crypto::Error or PasswordHash::Error."
            category :security
            version "3.0.0"
            presentation icon: "M7 20l4-16m2 16l4-16M6 9h14M4 15h14", color: "purple",
                          single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "password",
                  description: "Context path of the value to hash, e.g. password or checksum_source."
            output :resultVar, default: "hashed",
                   description: "Ctx key that receives the encoded hash string. Default hashed."
            enum :algorithm, ALGORITHMS, default: "sha256",
                 description: "bcrypt/scrypt/argon2: password hashes (self-salted). pbkdf2: HMAC-SHA256 KDF " \
                              "(needs salt). sha256/sha512: digests for checksums, not passwords. Default sha256."
            integer :cost, min: 4, max: 31, default: 12, visible: { algorithm: "bcrypt" },
                    description: "bcrypt cost factor (4-31). Default 12. Higher is slower; keep 10-14 on web workers."
            integer :iterations, min: 1000, max: MAX_ITERATIONS, default: 100_000,
                    visible: { algorithm: %w[pbkdf2 scrypt] },
                    description: "pbkdf2 HMAC rounds (default 100000, max 1000000). For scrypt this maps to a " \
                                 "time budget (100000 is about 0.2s)."
            input :salt, visible: { algorithm: %w[sha256 sha512 pbkdf2] },
                  description: "Context path of salt mixed into sha256/sha512 (prepended) or pbkdf2. Required " \
                               "for pbkdf2. Example: salt. bcrypt/scrypt/argon2 generate their own salt."
            input :pepper, visible: { algorithm: %w[sha256 sha512] },
                  description: "Context path of an extra secret appended to sha256/sha512 input, e.g. pepper. " \
                               "Not used for password algorithms or pbkdf2."
            enum :encoding, ENCODINGS, default: "hex",
                 visible: { algorithm: %w[sha256 sha512 pbkdf2] },
                 description: "Digest encoding: hex (default), base64, or base64url. Ignored for bcrypt, scrypt, " \
                              "and argon2, which return their own encoded strings."
            integer :timeCost, min: FlowchartRuntime::PasswordHash::ARGON2_TIME_COSTS.min,
                               max: FlowchartRuntime::PasswordHash::ARGON2_TIME_COSTS.max,
                               default: 2, visible: { algorithm: "argon2" }, group: :advanced,
                               description: "Argon2 time cost (iterations), 1-8. Default 2."
            integer :memoryCost, min: FlowchartRuntime::PasswordHash::ARGON2_MEMORY_COSTS.min,
                                 max: FlowchartRuntime::PasswordHash::ARGON2_MEMORY_COSTS.max,
                                 default: 16, visible: { algorithm: "argon2" }, group: :advanced,
                                 description: "Argon2 memory cost as log2 KiB, 8-17 (17 is 128 MiB). Default 16."
          end

          def generate_body
            body(
              attempt('"hash_data.failed"', FlowchartRuntime::Crypto::Error, FlowchartRuntime::PasswordHash::Error) do
                [
                  assign(:resultVar, hash_call),
                  "true"
                ]
              end
            )
          end

          private

          def hash_call
            algorithm = value(:algorithm).to_s
            case algorithm
            when *PASSWORD_ALGORITHMS then password_call(algorithm)
            when "pbkdf2" then pbkdf2_call
            else digest_call(algorithm)
            end
          end

          def password_call(algorithm)
            opts = case algorithm
                   when "bcrypt"
                     cost = value(:cost).to_i
                     cost == FlowchartRuntime::PasswordHash::DEFAULT_BCRYPT_COST ? [] : ["cost: #{read(:cost)}"]
                   when "scrypt" then ["iterations: #{read(:iterations)}"]
                   when "argon2" then argon2_opts
                   else []
                   end
            call = "FlowchartRuntime::PasswordHash.create(#{algorithm.inspect}, #{read(:sourceVariable)}.to_s"
            opts.empty? ? "#{call})" : "#{call}, #{opts.join(', ')})"
          end

          def argon2_opts
            opts = []
            opts << "t_cost: #{read(:timeCost)}" unless value(:timeCost).to_i == 2
            opts << "m_cost: #{read(:memoryCost)}" unless value(:memoryCost).to_i == 16
            opts
          end

          def pbkdf2_call
            parts = ["#{read(:sourceVariable)}.to_s", "salt: #{salt_expr}.to_s", "iterations: #{read(:iterations)}"]
            encoding = value(:encoding).to_s
            parts << "encoding: #{read(:encoding)}" unless encoding.empty? || encoding == "hex"
            "FlowchartRuntime::Crypto.encoded_pbkdf2(#{parts.join(', ')})"
          end

          def digest_call(algorithm)
            algo = DIGEST_ALGORITHMS.include?(algorithm) ? algorithm : "sha256"
            parts = [algo.inspect, read(:sourceVariable)]
            encoding = value(:encoding).to_s
            parts << "encoding: #{read(:encoding)}" unless encoding.empty? || encoding == "hex"
            parts << "salt: #{read(:salt)}" if present_input?(:salt)
            parts << "pepper: #{read(:pepper)}" if present_input?(:pepper)
            "FlowchartRuntime::Crypto.digest(#{parts.join(', ')})"
          end

          def salt_expr
            present_input?(:salt) ? read(:salt) : "nil"
          end

          def present_input?(name)
            value(name).to_s.strip.present?
          end
        end
      end
    end
  end
end
