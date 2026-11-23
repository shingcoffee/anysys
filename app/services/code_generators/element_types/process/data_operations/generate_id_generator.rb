# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module DataOperations
        class GenerateIdGenerator < BaseGenerator
          ID_TYPES = %w[uuid nanoid hex custom_pattern].freeze

          generator_metadata do
            description "Generates an identifier with SecureRandom: uuid (default), nanoid (short URL-safe code), hex (token), or custom_pattern (strftime plus a random suffix, e.g. ORD-%Y%m%d-). Optional prefix and separator produce values such as user_ followed by the id. Use assign_value for constants and hash_data for a digest of existing data. Writes resultVar. Fails with generate_id.failed on an unsupported type or empty nanoid alphabet."
            category :data_operations
            version "3.0.0"
            presentation icon: "M7 20l4-16m2 16l4-16M6 9h14M4 15h14", color: "purple",
                          single_use: false, privileged: false
          end

          config_schema do
            enum :idType, ID_TYPES, default: "uuid",
                 description: "Kind of identifier. uuid is a RFC 4122 id; nanoid is a short URL-safe code; hex is a random hex token; custom_pattern is Time.zone strftime plus six random characters."
            output :resultVar, default: "id",
                   description: "Ctx variable later steps read. Example: confirmation_code or order_id."
            integer :length, min: 1, max: 256, default: 21,
                    visible: { idType: %w[nanoid hex] },
                    description: "Character length for nanoid (default 21) or hex (even lengths preferred). Example: 8 for a short code."
            literal :alphabet, placeholder: true, visible: { idType: "nanoid" }, group: :advanced,
                    description: "Characters nanoid may use. Leave blank for the default URL-safe alphabet. Example: 0123456789ABCDEF."
            literal :pattern, placeholder: true, visible: { idType: "custom_pattern" },
                    description: "strftime pattern prepended to six random characters. Example: ORD-%Y%m%d- yields ORD-20261123-Ab12Cd."
            literal :prefix, placeholder: true, example: "user",
                    description: "Text prepended to the generated identifier. Example: user or ORD. Empty means no prefix."
            literal :separator, placeholder: true, example: "_",
                    description: "Text between the prefix and the identifier when prefix is set. Example: _ or -. Ignored when prefix is empty."
            flag :uppercase, default: false, group: :advanced,
                 description: "Uppercase the generated identifier (not the prefix). Default false."
          end

          def generate_body
            body(
              attempt('"generate_id.failed"', FlowchartRuntime::Id::Error) do
                [
                  assign(:resultVar, "FlowchartRuntime::Id.generate(#{id_args})"),
                  "true"
                ]
              end
            )
          end

          private

          def id_args
            type = value(:idType).to_s
            args = ["type: #{read(:idType)}"]
            length = read(:length)
            args << "size: #{length}" if type == "nanoid" && length != "21"
            args << "length: #{length}" if type == "hex" && length != "21"
            alphabet = optional_literal(:alphabet)
            args << "alphabet: #{alphabet}" unless alphabet == "nil"
            pattern = optional_literal(:pattern)
            args << "pattern: #{pattern}" unless pattern == "nil"
            prefix = optional_literal(:prefix)
            args << "prefix: #{prefix}" unless prefix == "nil"
            separator = optional_literal(:separator)
            args << "separator: #{separator}" unless separator == "nil"
            args << "uppercase: true" if read(:uppercase) == "true"
            args.join(", ")
          end

          def optional_literal(name)
            raw = value(name)
            raw.to_s.strip.empty? ? "nil" : read(name)
          end
        end
      end
    end
  end
end
