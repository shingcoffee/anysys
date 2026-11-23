# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module Utility
        class BarcodeGenerateGenerator < BaseGenerator
          SYMBOLOGIES = %w[code128 code39 ean13 ean8 upca itf codabar qr].freeze
          BARCODE_FORMATS = %w[code128 code39 ean13 ean8 upca itf codabar].freeze
          OUTPUT_FORMATS = %w[png svg jpg base64 ascii].freeze
          TEXT_FONTS = FlowchartRuntime::Barcode::ALLOWED_FONTS
          QR_OUTPUTS = %w[png svg base64 ascii].freeze
          BARCODE_OUTPUTS = %w[png svg jpg base64].freeze

          generator_metadata do
            description "Encodes sourceVariable (a SKU, ticket id, or URL) as a barcode or QR image " \
                        "and stores a hash on resultVar (default barcode_image) with bytes, content_type, " \
                        "filename, and data_uri for send_email HTML (img src) or template_render. " \
                        "format code128 (default) suits labels; ean13 needs a 12-digit payload plus " \
                        "check digit; qr encodes a URL or ticket. outputFormat png (default) or svg; " \
                        "svg can draw a human-readable line. Fails as barcode_generate.failed on empty " \
                        "or invalid payload (for example a non-numeric EAN)."
            category :utility
            version "2.0.0"
            presentation icon: "M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8h2a1 1 0 001-1V5a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1zm12 0h2a1 1 0 001-1V5a1 1 0 00-1-1h-2a1 1 0 00-1 1v2a1 1 0 001 1zM5 20h2a1 1 0 001-1v-2a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1z",
                         color: "gray", single_use: false, privileged: false
          end

          config_schema do
            input :sourceVariable, required: true, example: "sku",
                  description: "Ctx path of the payload to encode, such as sku, ticket_number, or " \
                               "checkout_url. Required. Empty values fail the step."
            enum :format, SYMBOLOGIES, default: "code128",
                 description: "Symbology. code128 (default) for SKUs and labels. ean13 / ean8 / upca " \
                              "for retail GTINs. code39, itf, and codabar for warehouse codes. qr for " \
                              "a URL or ticket payload."
            integer :width, min: 1, max: 32, default: 2, visible: { format: BARCODE_FORMATS },
                    description: "Module width in pixels for 1D barcodes (1-32). Default 2. Hidden for qr."
            integer :height, min: 1, max: 1000, default: 100, visible: { format: BARCODE_FORMATS },
                    description: "Bar height in pixels for 1D barcodes (1-1000). Default 100. Hidden for qr."
            integer :margin, min: 0, max: 100, default: 10,
                    description: "Quiet zone in pixels (1D) or modules (qr). Default 10. Use 0-100."
            enum :outputFormat, OUTPUT_FORMATS, default: "png",
                 description: "Image encoding. png (default) for PDF and email data_uri. svg for HTML " \
                              "and labels. jpg when a JPEG blob is required. base64 is a PNG string. " \
                              "ascii is QR text art only."
            flag :includeText, default: true, visible: { outputFormat: "svg" },
                 description: "When true (default), draw the payload under an SVG 1D barcode. Hidden " \
                              "unless outputFormat is svg. Ignored for qr."
            enum :textFont, TEXT_FONTS, default: "Helvetica", visible: { outputFormat: "svg" },
                 description: "Font for the SVG human-readable line: Helvetica (default), Arial, " \
                              "DejaVuSans, or FreeSans. Hidden unless outputFormat is svg."
            integer :size, min: 1, max: 40, default: 4, visible: { format: "qr" },
                    description: "QR module size in pixels (1-40). Default 4. Hidden unless format is qr."
            enum :errorCorrection, %w[L M Q H], default: "M", visible: { format: "qr" },
                 description: "QR error-correction level: L (~7%), M (default, ~15%), Q (~25%), H (~30%). " \
                              "Hidden unless format is qr."
            literal :colorDark, default: "#000000", placeholder: true, visible: { format: "qr" },
                    description: "QR dark-module colour as #RGB, #RRGGBB, or #RRGGBBAA. Default #000000. " \
                                 "Hidden unless format is qr."
            literal :colorLight, default: "#FFFFFF", placeholder: true, visible: { format: "qr" },
                    description: "QR light-module colour as #RGB, #RRGGBB, or #RRGGBBAA. Default #FFFFFF. " \
                                 "Hidden unless format is qr."
            output :resultVar, default: "barcode_image",
                   description: "Ctx variable for the artifact hash (bytes, content_type, filename, " \
                                "data_uri). Default barcode_image. Use data_uri in an email img src."
            validate do |cfg, errors|
              format = (cfg["format"].presence || "code128").to_s
              output = (cfg["outputFormat"].presence || "png").to_s
              allowed = format == "qr" ? QR_OUTPUTS : BARCODE_OUTPUTS
              errors.add(:outputFormat, :not_in_list, allowed: allowed.join(", ")) unless allowed.include?(output)
            end
          end

          def generate_body
            attempt('"barcode_generate.failed"', FlowchartRuntime::Barcode::Error) do
              [
                assign(:resultVar, artifact_call),
                "true"
              ]
            end
          end

          private

          def artifact_call
            qr = value(:format) == "qr"
            args = [
              read(:sourceVariable),
              ("format: #{literal(value(:format).to_s.to_sym)}" unless value(:format).to_s == "code128"),
              ("output: #{literal(value(:outputFormat).to_s.to_sym)}" unless value(:outputFormat).to_s == "png")
            ]
            if qr
              args << ("size: #{read(:size)}" unless value(:size) == 4)
              args << ("level: #{literal(value(:errorCorrection).to_s.downcase.to_sym)}" unless value(:errorCorrection).to_s.downcase == "m")
              args << ("margin: #{read(:margin)}" unless value(:margin) == 10)
              args << ("color_dark: #{read(:colorDark)}" unless value(:colorDark).to_s == "#000000")
              args << ("color_light: #{read(:colorLight)}" unless value(:colorLight).to_s == "#FFFFFF")
            else
              args << ("width: #{read(:width)}" unless value(:width) == 2)
              args << ("height: #{read(:height)}" unless value(:height) == 100)
              args << ("margin: #{read(:margin)}" unless value(:margin) == 10)
              if value(:outputFormat) == "svg"
                args << ("include_text: #{read(:includeText)}" unless value(:includeText) == false)
                args << ("text_font: #{read(:textFont)}" unless value(:textFont).to_s == "Helvetica")
              end
            end
            "FlowchartRuntime::Barcode.artifact(#{args.compact.join(', ')})"
          end
        end
      end
    end
  end
end
