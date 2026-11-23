# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class GenerateDocumentGenerator < BaseGenerator
          PAGE_SIZES = %w[a4 letter legal].freeze
          ORIENTATIONS = %w[portrait landscape].freeze

          generator_metadata do
            description "Renders a PDF (title, body, optional table) with Prawn and stores an " \
                        "ActiveStorage blob tagged with customer_id. Use send_email " \
                        "attachmentsVariable to attach it, or upload_file to push the blob " \
                        "elsewhere. Reads title/body/header/footer/filename as Liquid, " \
                        "sourceVariable rows, columns, pageSize, orientation, and pageNumbers. " \
                        "Writes resultVar (default document) as a hash: blob_id, signed_id, " \
                        "filename, content_type, byte_size, checksum, customer_id. Fails with " \
                        "generate_document.failed on Prawn or template errors."
            category :file_operations
            version "1.2.0"
            presentation icon: "M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z",
                         color: "teal", single_use: false, privileged: false
          end

          config_schema do
            template :title, required: true, example: "Invoice {{ name }}",
                     description: "Document title. Liquid placeholders resolve from ctx, e.g. Invoice {{ name }}."
            template :body, required: true, example: "Hello {{ name }}\n\n## Details", multiline: true,
                     description: "Body paragraphs. Liquid placeholders resolve from ctx. Lines starting with ## become headings."
            input :sourceVariable, example: "rows",
                  description: "ctx path of optional table rows (array of hashes), e.g. rows or line_items. Blank skips the table."
            mapping :columns, key: :literal, value: :literal, default: [],
                    description: "Table column header mapped to a row field, e.g. Item => item, Qty => qty. Empty prints row values in hash order."
            enum :pageSize, PAGE_SIZES, default: "a4",
                 description: "Paper size of the generated PDF: a4 (default), letter, or legal."
            enum :orientation, ORIENTATIONS, default: "portrait",
                 description: "Page layout: portrait (default) or landscape."
            template :header, default: "", group: :advanced,
                     description: "Optional header drawn at the top of every page. Liquid placeholders resolve from ctx. Blank draws none."
            template :footer, default: "", group: :advanced,
                     description: "Optional footer drawn at the bottom of every page. Liquid placeholders resolve from ctx. Blank draws none."
            flag :pageNumbers, default: false, group: :advanced,
                 description: "When true, prints a page number (n / total) on every page. Default false."
            template :filename, default: "document.pdf",
                     description: "Filename stored on the ActiveStorage blob, e.g. invoice-{{ name }}.pdf. Default document.pdf; .pdf is appended if missing."
            output :resultVar, default: "document",
                   description: "ctx key for the blob hash (default document). Pass this path to send_email attachmentsVariable to attach the PDF."
          end

          def generate_body
            attempt('"generate_document.failed"', FlowchartRuntime::Document::Error, FlowchartRuntime::Template::Error) do
              [assign(:resultVar, "FlowchartRuntime::Document.pdf(#{pdf_args})")]
            end
          end

          private

          def pdf_args
            [
              "title: #{read(:title)}",
              "body: #{read(:body)}",
              optional_kw("filename", read(:filename), '"document.pdf"'),
              optional_kw("rows", rows_source, "nil"),
              optional_kw("columns", read(:columns), "{}"),
              optional_kw("page_size", read(:pageSize), '"a4"'),
              optional_kw("orientation", read(:orientation), '"portrait"'),
              optional_kw("header", header_source, '""'),
              optional_kw("footer", footer_source, '""'),
              optional_kw("page_numbers", read(:pageNumbers), "false"),
              "customer_id: ctx[:customer_id]"
            ].compact.join(", ")
          end

          def rows_source
            value(:sourceVariable).to_s.strip.present? ? read(:sourceVariable) : "nil"
          end

          def header_source
            value(:header).to_s.present? ? read(:header) : '""'
          end

          def footer_source
            value(:footer).to_s.present? ? read(:footer) : '""'
          end

          def optional_kw(name, source, default)
            "#{name}: #{source}" unless source == default
          end
        end
      end
    end
  end
end
