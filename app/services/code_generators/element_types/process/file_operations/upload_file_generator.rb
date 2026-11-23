# frozen_string_literal: true

module CodeGenerators
  module ElementTypes
    module Process
      module FileOperations
        class UploadFileGenerator < BaseGenerator
          BoundView = Data.define(:name, :attribute_slugs, :file_slugs)

          generator_metadata do
            description "Attaches a file to a File or Image field through Active Storage. Use after " \
                        "generate_file, download_file or generate_document to keep the file on the record. " \
                        "Reads modelVariable, fileField and sourceVariable. Replaces a single-file field; " \
                        "appends to a multiple-file field. Saves through Entries::Save unless saveRecord is " \
                        "off, so accepted types, the 25 MB limit and the image check refuse a bad file. Writes " \
                        "resultVar with {blob_id, signed_id, filename, content_type, byte_size}. Fails with " \
                        "upload_file.failed when the record, field or file is missing or belongs to another tenant."
            category :file_operations
            version "6.1.0"
            presentation icon: "M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12",
                         color: "green", single_use: false, privileged: false
          end

          config_schema do
            input :modelVariable, default: "model",
                  description: "Ctx path of the EntityEntry that receives the file, such as model (the page record) or order."
            entity_attribute :fileField, of: :bound, example: "contract", required: true,
                             description: "Slug of the record's File or Image attribute that receives the file, such as contract or photo. " \
                                          "Any other kind of attribute is refused."
            input :sourceVariable, required: true, example: "invoice_file",
                  description: "Ctx path of the file: a file payload {filename, content, content_type} from generate_file or " \
                               "download_file, a generate_document result ({blob_id, ...}), raw bytes, or another record's " \
                               "file field such as customer_record.photo."
            template :filename, group: :advanced, example: "invoice-{{ order.number }}.pdf",
                     description: "Optional Liquid filename that replaces the source's, such as invoice-{{ order.number }}.pdf. " \
                                  "Blank keeps the source filename (upload.bin for raw bytes)."
            flag :saveRecord, default: true,
                 description: "On (default) saves the record now, so the file is stored and checked. Off only stages the " \
                              "file for a later save_model or update_model step on the same record."
            output :resultVar, default: "uploaded_file",
                   description: "Ctx variable that receives {blob_id, signed_id, filename, content_type, byte_size} for the " \
                                "attached file. blob_id and signed_id are nil while saveRecord is off."

            validate do |_cfg, errors|
              entity = bound_entity
              slug = value(:fileField).to_s
              if entity.respond_to?(:file_slugs) && entity.attribute_slugs.include?(slug) && !entity.file_slugs.include?(slug)
                errors.add(:fileField, :not_file_attribute, attribute: slug, entity: entity.name.to_s)
              end
            end
          end

          def generate_body
            body(
              attempt('"upload_file.failed"', FlowchartRuntime::FileUpload::Error, FlowchartRuntime::Template::Error) do
                [
                  "uploaded = FlowchartRuntime::FileUpload.attach(#{attach_args})",
                  "next false unless uploaded",
                  assign(:resultVar, "uploaded")
                ]
              end
            )
          end

          # The field is checked only on the page's own record, whose entity is known here.
          def bound_entity
            raw = context.is_a?(Hash) ? (context[:bound_entity] || context["bound_entity"]) : nil
            return unless raw && value(:modelVariable).to_s.in?(["", "model"])
            return raw if raw.respond_to?(:attribute_slugs)

            rows = Array(raw.try(:property_schema_json)).grep(Hash)
            BoundView.new(raw.try(:name), rows.filter_map { |row| row["name_slug"].to_s.presence },
                          rows.select { |row| EntityEntry.file_attribute?(row) }.map { |row| row["name_slug"].to_s })
          end

          private

          def attach_args
            [
              "ctx",
              read(:modelVariable),
              read(:fileField),
              read(:sourceVariable),
              ("filename: #{read(:filename)}" if value(:filename).to_s.strip.present?),
              ("save: false" unless value(:saveRecord))
            ].compact.join(", ")
          end
        end
      end
    end
  end
end
