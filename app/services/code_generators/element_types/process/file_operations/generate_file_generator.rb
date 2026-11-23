# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class GenerateFileGenerator < BaseGenerator
          FILE_TYPES = %w[csv xlsx json txt].freeze
          LINE_ENDINGS = %w[lf crlf].freeze

          generator_metadata do
            description "Exports a collection of hashes or EntityEntry rows to a CSV, XLSX, JSON, or " \
                        "TXT file payload {filename, content, content_type} in resultVar. Use this for " \
                        "spreadsheet downloads and Excel-friendly CSVs (UTF-8 with BOM by default). For " \
                        "a designed PDF with title, body, and table, use generate_document instead. " \
                        "Reads sourceVariable. Column headers that look like I18n keys are translated in " \
                        "the run locale; dates are formatted with I18n.l. upload_file, compress_files, " \
                        "and send_email attachments consume the payload. Fails with generate_file.failed " \
                        "when the type is unknown or the workbook cannot be built."
            category :file_operations
            version "5.0.0"
            presentation icon: "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z",
                         color: "teal", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "rows",
                  description: "Ctx path of the rows to export, for example rows or records. " \
                               "Each item is a hash or EntityEntry; attribute slugs are read through flowchart_value."
            output :resultVar, default: "generated_file",
                   description: "Ctx variable that receives the file payload {filename, content, content_type} " \
                                "for upload_file, compress_files, or send_email attachments."
            enum :fileType, FILE_TYPES, default: "csv",
                 description: "Output format. csv is UTF-8 text (Excel BOM on by default); xlsx is an Excel " \
                              "workbook; json is a JSON array; txt is one line per row. Use generate_document for PDFs."
            mapping :columns, key: :literal, value: :entity_attribute, default: [], visible: { fileType: %w[csv xlsx] },
                    description: "Header-to-field map for csv and xlsx. key is the header text or an I18n key " \
                                 "(resolved in the run locale); value is the row attribute slug such as name. Empty uses every key on the first row."
            literal :sheetName, default: "Sheet1", placeholder: true, visible: { fileType: "xlsx" },
                    description: "Worksheet name for xlsx, for example Orders. Must be 1-31 Excel characters and cannot contain []*/\\?:."
            flag :autoFilter, default: false, visible: { fileType: "xlsx" },
                 description: "When true, enables the Excel auto-filter on the header row so staff can sort and filter in Excel."
            flag :pretty, default: false, visible: { fileType: "json" },
                 description: "When true, pretty-prints JSON with indentation. Leave off for compact machine-readable dumps."
            enum :lineEnding, LINE_ENDINGS, default: "lf", visible: { fileType: "txt" },
                 description: "Line break for txt. lf is Unix newline; crlf is Windows CRLF for Notepad-friendly files."
            template :filenameTemplate, placeholder: true,
                     description: "Liquid filename such as orders-{{ \"now\" | date: \"%Y%m%d\" }}.csv. " \
                                  "When blank, export.<fileType> is used."
            literal :delimiter, default: ",", placeholder: true, visible: { fileType: "csv" },
                    description: "CSV column separator. Use a comma (default) for Excel in the US; use a semicolon for many European locales."
            flag :headerRow, default: true, visible: { fileType: "csv" },
                 description: "When true (default), write a header row of column names. Turn off only for headerless machine imports."
            flag :quoteStrings, default: false, visible: { fileType: "csv" }, group: :advanced,
                 description: "When true, quote every CSV field. Use this when values may contain the delimiter, quotes, or newlines."
            flag :includeBom, default: true, visible: { fileType: "csv" },
                 description: "When true (default), prefix CSV with a UTF-8 BOM so Microsoft Excel recognises the encoding. Turn off for strict UTF-8 consumers."
            literal :nestedSeparator, default: ".", placeholder: true, visible: { fileType: "csv" }, group: :advanced,
                    description: "Separator for nested hash paths in csv column values, for example address.city with '.'. Default is a dot."
          end

          def generate_body
            body(
              attempt(
                '"generate_file.failed"',
                FlowchartRuntime::FileGenerate::Error,
                FlowchartRuntime::Template::Error
              ) do
                [assign(:resultVar, apply_call)]
              end
            )
          end

          private

          def apply_call
            type = value(:fileType).to_s
            args = [
              read(:sourceVariable),
              "file_type: #{read(:fileType)}",
              *type_kwargs(type),
              optional_kw("filename", filename_source, "nil"),
              "locale: ctx[:locale]"
            ].compact
            "FlowchartRuntime::FileGenerate.apply(#{args.join(', ')})"
          end

          def type_kwargs(type)
            case type
            when "csv"
              [
                optional_kw("columns", read(:columns), "{}"),
                optional_kw("delimiter", read(:delimiter), '","'),
                optional_kw("header_row", read(:headerRow), "true"),
                optional_kw("quote_strings", read(:quoteStrings), "false"),
                optional_kw("include_bom", read(:includeBom), "true"),
                optional_kw("nested_separator", read(:nestedSeparator), '"."')
              ]
            when "xlsx"
              [
                optional_kw("columns", read(:columns), "{}"),
                optional_kw("sheet_name", read(:sheetName), '"Sheet1"'),
                optional_kw("auto_filter", read(:autoFilter), "false")
              ]
            when "json"
              [optional_kw("pretty", read(:pretty), "false")]
            when "txt"
              [optional_kw("line_ending", read(:lineEnding), '"lf"')]
            else
              []
            end
          end

          def filename_source
            value(:filenameTemplate).present? ? read(:filenameTemplate) : "nil"
          end

          def optional_kw(name, source, default)
            "#{name}: #{source}" unless source == default
          end
        end
      end
    end
  end
end
