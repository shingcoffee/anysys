# frozen_string_literal: true

require "stringio"

module FlowchartRuntime
  # Attaches a file to a record's File or Image field, the field's own
  # has_one_attached / has_many_attached (EntityEntryFiles). The record's
  # accepted types, size limit and image check run when it saves.
  module FileUpload
    class Error < StandardError; end

    UPLOADS = [ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile].freeze

    module_function

    # Metadata of the attached file, or false when saving the record was
    # refused (its reasons are on ctx, as for any save).
    def attach(ctx, record, field, source, filename: nil, save: true)
      raise Error, "record is required" unless record.is_a?(EntityEntry)
      raise Error, "record is not in this tenant" unless record.customer_id.to_s == ctx[:customer_id].to_s

      slug = field.to_s
      raise Error, "#{slug} is not a file field of this record" unless record.file_slug?(slug)

      attachables = attachables_for(ctx, source, filename.to_s.presence)
      raise Error, "there is no file to attach" if attachables.empty?

      several = record.class.reflect_on_attachment(slug).macro == :has_many_attached
      record.public_send("#{slug}=", several ? record.file_blobs(slug) + attachables : attachables.last)
      blob = record.pending_file_blobs(slug).last
      return false if save && !Entries.save(ctx, record)

      metadata(blob)
    rescue ActiveStorage::Error, ActiveSupport::MessageVerifier::InvalidSignature => error
      raise Error, error.message
    end

    def attachables_for(ctx, source, filename)
      case source
      when nil then []
      when Array then source.flat_map { |item| attachables_for(ctx, item, filename) }
      when ActiveStorage::Attached::One, ActiveStorage::Attached::Many
        source.attached? ? attachables_for(ctx, source.respond_to?(:blobs) ? source.blobs.to_a : source.blob, filename) : []
      when ActiveStorage::Attachment then attachables_for(ctx, source.blob, filename)
      when ActiveStorage::Blob then [renamed(tenant_blob!(ctx, source), filename)]
      when *UPLOADS
        [filename ? { io: source.open, filename: filename, content_type: source.content_type } : source]
      when Hash then [hash_attachable(ctx, source, filename)]
      else [payload_attachable(source, filename)]
      end
    end

    # A generate_document result names a stored blob; a file payload carries
    # its bytes.
    def hash_attachable(ctx, source, filename)
      blob_id = source["blob_id"] || source[:blob_id]
      signed_id = source["signed_id"] || source[:signed_id]
      return payload_attachable(source, filename) unless blob_id || signed_id

      blob = blob_id ? ActiveStorage::Blob.find_by(id: blob_id) : ActiveStorage::Blob.find_signed!(signed_id)
      raise Error, "the file was not found" unless blob

      renamed(tenant_blob!(ctx, blob), filename)
    end

    def payload_attachable(source, filename)
      payload = FilePayload.extract(source)
      raise Error, "there is no file to attach" if payload[:content].empty?

      { io: StringIO.new(payload[:content]), filename: filename || payload[:filename] || "upload.bin",
        content_type: payload[:content_type] }
    end

    def tenant_blob!(ctx, blob)
      return blob if blob.customer_id.present? && blob.customer_id.to_s == ctx[:customer_id].to_s

      raise Error, "the file was not found"
    end

    # A stored file keeps its name; a new one copies it under +filename+.
    def renamed(blob, filename)
      return blob if filename.nil? || filename == blob.filename.to_s

      { io: StringIO.new(blob.download), filename: filename, content_type: blob.content_type }
    end

    def metadata(blob)
      {
        "blob_id" => blob&.id,
        "signed_id" => (blob.signed_id if blob&.persisted?),
        "filename" => blob&.filename&.to_s,
        "content_type" => blob&.content_type,
        "byte_size" => blob&.byte_size
      }
    end
    private_class_method :attachables_for, :hash_attachable, :payload_attachable, :tenant_blob!, :renamed, :metadata
  end
end
