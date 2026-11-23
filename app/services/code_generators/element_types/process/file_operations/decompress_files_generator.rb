# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class DecompressFilesGenerator < BaseGenerator
          FORMATS = %w[auto zip tar gz tar_gz].freeze

          generator_metadata do
            description "Extracts a ZIP (or an auto-detected tar/gz vendor archive) into an array of " \
                        "file payloads {filename, content, content_type} in resultVar. Pair with " \
                        "download_file or a record attachment, then bulk_import a CSV inside. Zip-slip " \
                        "paths and decompression bombs are refused (entry count and expanded-byte caps). " \
                        "Reads sourceVariable (bytes or a file payload). Fails with decompress_files.failed " \
                        "on a corrupt archive, path traversal, or a cap breach."
            category :file_operations
            version "4.0.0"
            presentation icon: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4",
                         color: "purple", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "archive",
                  description: "Ctx path of the archive bytes or file payload, for example archive " \
                               "from download_file or compress_files. Nested paths use Step.dig."
            output :resultVar, default: "extracted",
                   description: "Ctx variable that receives an array of file payloads " \
                                "{filename, content, content_type}, one per extracted file, for upload_file or bulk_import."
            enum :format, FORMATS, default: "auto",
                 description: "Archive kind. auto sniffs ZIP (PK), gzip, or tar; zip is the usual export; " \
                              "tar, gz, and tar_gz accept vendor dumps that download_file fetched. Prefer auto."
            literal :filter, placeholder: true,
                    description: "Optional fnmatch of names to keep, for example *.csv. Blank keeps every safe entry."
            integer :maxEntries, min: 1, max: FlowchartRuntime::Archive::MAX_ENTRIES, group: :advanced,
                    description: "Maximum archive members to open (1-1000). Leave blank for the platform cap. " \
                                 "Stops a zip bomb that lists thousands of files."
            integer :maxTotalBytes, min: 1, max: FlowchartRuntime::Archive::MAX_OUTPUT_BYTES, group: :advanced,
                    description: "Maximum expanded bytes across extracted files. Leave blank for the platform cap (100 MB)."
          end

          def generate_body
            body(
              attempt('"decompress_files.failed"', FlowchartRuntime::Archive::Error, FlowchartRuntime::SandboxPath::Error) do
                [assign(:resultVar, unpack_call)]
              end
            )
          end

          private

          def unpack_call
            args = [
              read(:sourceVariable),
              optional_kw("format", read(:format), '"auto"'),
              optional_kw("filter", filter_source, "nil"),
              optional_kw("max_entries", optional_int(:maxEntries), "nil"),
              optional_kw("max_total_bytes", optional_int(:maxTotalBytes), "nil")
            ].compact
            "FlowchartRuntime::Archive.unpack(#{args.join(', ')})"
          end

          def filter_source
            value(:filter).to_s.present? ? read(:filter) : "nil"
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
