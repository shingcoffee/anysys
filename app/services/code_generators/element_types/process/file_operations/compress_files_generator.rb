# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class CompressFilesGenerator < BaseGenerator
          generator_metadata do
            description "Zips ctx files into one archive payload {filename, content, content_type} " \
                        "for emailing or attaching. Map archive names to ctx variables that hold bytes " \
                        "or file payloads from generate_file or download_file. Use decompress_files to " \
                        "extract an incoming ZIP. Only ZIP is produced. Writes resultVar. Fails with " \
                        "compress_files.failed when there are no entries, an entry is too large, or a " \
                        "name is zip-slip-unsafe."
            category :file_operations
            version "4.0.0"
            presentation icon: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12",
                         color: "purple", single_use: false, privileged: false
          end

          config_schema do
            mapping :entries, key: :literal, value: :literal, required: true,
                    example: [{ "key" => "data.txt", "value" => "file_data" }],
                    description: "Archive entry name mapped to a ctx variable. " \
                                 "Example: key data.txt, value generated_file. " \
                                 "The variable may hold raw bytes or a file payload; content is zipped under the key name."
            mapping :literalEntries, key: :literal, value: :literal, default: [],
                    description: "Archive entry name mapped to literal UTF-8 text, for a static README.txt " \
                                 "inside the ZIP. Leave empty when every entry comes from ctx."
            integer :compressionLevel, min: 0, max: 9,
                    description: "ZIP deflate level from 0 (store) to 9 (smallest). Leave blank for the RubyZip default."
            flag :includeHidden, default: false,
                    description: "When true, keep entry names that start with a dot, such as .env. Default skips those names."
            template :filenameTemplate, placeholder: true,
                    description: "ZIP filename such as orders.zip or orders-{{ \"now\" | date: \"%Y%m%d\" }}.zip. " \
                                 "When blank, the payload filename is archive.zip."
            output :resultVar, default: "archive",
                    description: "Ctx variable that receives the ZIP file payload {filename, content, content_type} " \
                                 "for upload_file, send_email attachments, or a later download step."

            validate do |_cfg, errors|
              sources = Array(value(:entries))
              literals = Array(value(:literalEntries))
              errors.add(:entries, :required) if sources.empty? && literals.empty?
            end
          end

          def generate_body
            body(
              attempt(
                '"compress_files.failed"',
                FlowchartRuntime::Archive::Error,
                FlowchartRuntime::Template::Error
              ) do
                [assign(:resultVar, pack_call)]
              end
            )
          end

          private

          def pack_call
            args = [
              "ctx",
              "sources: #{read(:entries)}",
              optional_kw("literals", read(:literalEntries), "{}"),
              optional_kw("compression_level", optional_int(:compressionLevel), "nil"),
              optional_kw("include_hidden", read(:includeHidden), "false"),
              optional_kw("filename", filename_source, "nil")
            ].compact
            "FlowchartRuntime::Archive.pack(#{args.join(', ')})"
          end

          def filename_source
            value(:filenameTemplate).to_s.present? ? read(:filenameTemplate) : "nil"
          end

          def optional_int(field)
            value(field).nil? ? "nil" : read(field)
          end

          def optional_kw(name, source, default)
            "#{name}: #{source}" unless source == default
          end
        end
      end
    end
  end
end
