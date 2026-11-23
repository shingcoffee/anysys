# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Security
        # Shared symmetric-cipher key resolution for encrypt_data / decrypt_data.
        #
        # Both generators MUST resolve a key identically, otherwise a payload
        # encrypted by one cannot be decrypted by the other. Every emitted
        # expression is built from value()/read() — no raw config splice.
        module KeyResolution
          include CodeGenerators::Shared::IdentifierSanitizer

          KEY_SOURCES = %w[credentials env ctx derived].freeze
          SECRET_SOURCES = %w[credentials env ctx].freeze
          ENV_NAME_RE = /\A[A-Za-z_][A-Za-z0-9_]*\z/
          CREDENTIAL_SEGMENT_RE = /\A[a-z_][a-zA-Z0-9_]*\z/
          DERIVED_SALT_NAMESPACE = "flowchart.cipher"

          def self.validate(cfg, errors)
            validate_key_source(cfg, errors)
            validate_derived(cfg, errors)
            validate_key_path(cfg, errors)
          end

          def self.validate_secret(cfg, errors, source_key: "secretSource", path_key: "secretVariable")
            source = cfg[source_key].presence || "credentials"
            path = cfg[path_key].to_s.strip
            if path.empty?
              errors.add(path_key.to_sym, :required) if %w[env ctx].include?(source.to_s)
              return
            end

            case source.to_s
            when "env"
              errors.add(path_key.to_sym, :invalid_env_name, value: path) unless ENV_NAME_RE.match?(path)
            when "ctx"
              errors.add(path_key.to_sym, :invalid_identifier) unless CREDENTIAL_SEGMENT_RE.match?(path)
            when "credentials"
              bad = path.split(".").map(&:strip).reject(&:empty?)
                        .reject { |segment| CREDENTIAL_SEGMENT_RE.match?(segment) }
              errors.add(path_key.to_sym, :invalid_credential_path, value: bad.join(", ")) if bad.any?
            end
          end

          def self.validate_key_source(cfg, errors)
            return if cfg["keySource"].blank? || KEY_SOURCES.include?(cfg["keySource"].to_s)

            errors.add(:keySource, :not_in_list, allowed: KEY_SOURCES.join(", "))
          end

          def self.validate_derived(cfg, errors)
            return unless cfg["keySource"].to_s == "derived"
            return if cfg["deriveKeyFrom"].present?

            errors.add(:deriveKeyFrom, :required)
          end

          def self.validate_key_path(cfg, errors)
            source = cfg["keySource"].presence || "credentials"
            path = cfg["keyPath"].to_s.strip
            if path.empty?
              errors.add(:keyPath, :required) if %w[env ctx].include?(source.to_s)
              return
            end

            case source.to_s
            when "env"
              errors.add(:keyPath, :invalid_env_name, value: path) unless ENV_NAME_RE.match?(path)
            when "ctx"
              errors.add(:keyPath, :invalid_identifier) unless CREDENTIAL_SEGMENT_RE.match?(path)
            when "credentials"
              bad = path.split(".").map(&:strip).reject(&:empty?)
                        .reject { |segment| CREDENTIAL_SEGMENT_RE.match?(segment) }
              errors.add(:keyPath, :invalid_credential_path, value: bad.join(", ")) if bad.any?
            end
          end

          def key_resolution_line(variable = "cipher_key")
            <<~RUBY.chomp
              #{variable} = FlowchartRuntime::Cipher.resolve_key do
                #{key_material_expression}
              end
            RUBY
          end

          def key_material_expression
            case value(:keySource).to_s
            when "env" then env_key_expression
            when "ctx" then ctx_key_expression
            when "derived" then derived_key_expression
            else credentials_key_expression
            end
          end

          def token_secret_expression(source_field: :secretSource, path_field: :secretVariable)
            path = value(path_field).to_s.strip
            case value(source_field).to_s
            when "env"
              name = ENV_NAME_RE.match?(path) ? path : "JWT_SECRET"
              "ENV.fetch(#{name.inspect}, nil)"
            when "ctx"
              key = safe_ident?(path) ? path : "secret"
              "ctx[:#{key}]"
            else
              segments = path.split(".").map(&:strip).reject(&:empty?)
              return "Rails.application.secret_key_base" if segments.empty?
              return "Rails.application.secret_key_base" unless segments.all? { |s| CREDENTIAL_SEGMENT_RE.match?(s) }

              "Rails.application.credentials.dig(#{safe_symbols(segments)})"
            end
          end

          private

          def env_key_expression
            name = value(:keyPath).to_s.strip
            return missing_key_path_expression("env") unless ENV_NAME_RE.match?(name)

            "ENV.fetch(#{name.inspect})"
          end

          def ctx_key_expression
            name = value(:keyPath).to_s.strip
            return missing_key_path_expression("ctx") unless safe_ident?(name)

            "ctx[:#{name}]"
          end

          def missing_key_path_expression(source)
            "raise(FlowchartRuntime::Cipher::Error, #{("keyPath is required when keySource is #{source}").inspect})"
          end

          def credentials_key_expression
            segments = value(:keyPath).to_s.split(".").map(&:strip).reject(&:empty?)
            return "Rails.application.secret_key_base" if segments.empty?
            return "Rails.application.secret_key_base" unless segments.all? { |s| CREDENTIAL_SEGMENT_RE.match?(s) }

            "Rails.application.credentials.dig(#{safe_symbols(segments)})"
          end

          def derived_key_expression
            passphrase = read(:deriveKeyFrom)
            "FlowchartRuntime::Cipher.key_from_passphrase(#{passphrase}.to_s, salt: #{derived_salt_expression})"
          end

          def derived_salt_expression
            suffix = value(:deriveKeySalt).to_s.strip
            %("#{DERIVED_SALT_NAMESPACE}.\#{ctx[:customer_id]}." + #{suffix.inspect})
          end
        end
      end
    end
  end
end
