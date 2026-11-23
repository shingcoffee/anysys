# frozen_string_literal: true

# File and Image attributes are Active Storage attachments, never values in
# the JSON data column: EntityEntry.build_for declares has_one_attached for
# each (has_many_attached when the attribute takes several files), so page
# uploads, Reform contracts and flowchart steps all attach the Rails way.
module EntityEntryFiles
  extend ActiveSupport::Concern

  HTML_TYPES = %w[file image].freeze
  MAX_BYTES = 25.megabytes
  UPLOADS = [ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile].freeze
  # What Marcel calls a file it can only tell is an Office or zip container.
  CONTAINER_TYPES = %w[application/x-ole-storage application/zip].freeze

  included do
    before_save :stamp_file_blob_tenant
    validate :validate_file_attachments
    # A record destroyed through EntityEntry itself has no attachment
    # reflections, so nothing removed its files by name.
    after_destroy_commit :purge_file_attachments
  end

  class_methods do
    def file_attribute?(attribute)
      attribute.is_a?(Hash) && HTML_TYPES.include?(attribute["html_type"].to_s) &&
        %w[Calculated Computed].exclude?(attribute["type"])
    end

    def multiple_files?(attribute)
      config = attribute.is_a?(Hash) ? attribute["config"] : nil
      config.is_a?(Hash) && ActiveModel::Type::Boolean.new.cast(config["multiple"]) == true
    end

    # slug => attribute for each attachment this class declares; none on
    # EntityEntry itself.
    def file_attributes
      @file_attributes ||= {}
    end

    private

    # A blank value (an empty file input) or the attachment itself (a
    # contract syncing an untouched field back) keeps the stored files.
    def declare_file_attachment(attribute)
      slug = attribute["name_slug"]
      file_attributes[slug] = attribute

      if multiple_files?(attribute)
        has_many_attached slug
        define_method("#{slug}=") do |attachables|
          return if attachables.is_a?(ActiveStorage::Attached)

          attachables = Array.wrap(attachables).compact_blank.map { |attachable| undeclared_type(attachable) }
          super(attachables) if attachables.any?
        end
      else
        has_one_attached slug
        define_method("#{slug}=") do |attachable|
          attachable = attachable.compact_blank.last if attachable.is_a?(Array)
          super(undeclared_type(attachable)) unless attachable.blank? || attachable.is_a?(ActiveStorage::Attached)
        end
      end
    end
  end

  def file_slug?(slug) = self.class.file_attributes.key?(slug.to_s)

  # The saved attachments of +slug+, read by record so it also works on
  # EntityEntry itself, which declares none.
  def stored_attachments(slug)
    return ActiveStorage::Attachment.none if new_record?

    ActiveStorage::Attachment.where(record_type: EntityEntry.polymorphic_name, record_id: id, name: slug.to_s)
                             .includes(:blob).order(:id)
  end

  # The blobs +slug+ holds, pending ones included.
  def file_blobs(slug)
    attached = public_send(slug)
    return [] unless attached.attached?

    attached.respond_to?(:blobs) ? attached.blobs.to_a : [attached.blob]
  end

  # Templates and exports see a file field as its filename, or its filenames
  # when it takes several.
  def file_names
    self.class.file_attributes.to_h do |slug, attribute|
      names = file_blobs(slug).map { |blob| blob.filename.to_s }
      [slug, self.class.multiple_files?(attribute) ? names : names.first]
    end
  end

  # Blobs being attached to +slug+ that it does not hold yet.
  def pending_file_blobs(slug)
    change = attachment_changes[slug.to_s]
    blobs = change.respond_to?(:blobs) ? change.blobs : Array(change.try(:blob))
    stored = stored_attachments(slug).pluck(:blob_id)
    blobs.compact.reject { |blob| blob.persisted? && stored.include?(blob.id) }
  end

  private

  # A new file's type is identified from its bytes and name, never taken from
  # its sender: a browser calls a CSV an Excel sheet, and a visitor can call a
  # program a PDF. A String is a stored blob's signed id, and a stored blob is
  # checked against the record's tenant on validation.
  def undeclared_type(attachable)
    case attachable
    when *UPLOADS
      { io: attachable.respond_to?(:open) ? attachable.open : attachable, filename: attachable.original_filename }
    when Hash then attachable.symbolize_keys.except(:content_type)
    else attachable
    end
  end

  def stamp_file_blob_tenant
    attachment_changes.each_value do |change|
      blobs = change.respond_to?(:blobs) ? change.blobs : [change.try(:blob)]
      blobs.each { |blob| blob.customer_id = customer_id if blob&.new_record? }
    end
  end

  def validate_file_attachments
    self.class.file_attributes.each do |slug, attribute|
      pending_file_blobs(slug).filter_map { |blob| file_error(attribute, blob) }.uniq
                              .each { |message| errors.add(slug.to_sym, message) }
    end
  end

  # Active Storage identifies each blob's content type from its bytes before
  # its name, so a renamed PDF or program does not pass as an image. A stored
  # blob (a signed id, a copied file) must be one of this record's tenant.
  def file_error(attribute, blob)
    accept = accepted_file_types(attribute)
    if blob.persisted? && (blob.customer_id.nil? || blob.customer_id != customer_id)
      I18n.t("maint_core.errors.validations.file_not_found")
    elsif blob.byte_size.to_i > MAX_BYTES
      I18n.t("maint_core.errors.validations.file_too_large", max: ActiveSupport::NumberHelper.number_to_human_size(MAX_BYTES))
    elsif attribute["html_type"] == "image" && !blob.image?
      I18n.t("maint_core.errors.validations.file_not_image")
    elsif accept.any? && accept.none? { |type| file_type_matches?(blob, type) }
      I18n.t("maint_core.errors.validations.file_type_not_accepted", types: accept.join(", "))
    end
  end

  def accepted_file_types(attribute)
    config = attribute["config"]
    (config.is_a?(Hash) ? config["accept"] : nil).to_s.split(",").map(&:strip).reject(&:empty?)
  end

  # An HTML accept token: an extension (".pdf"), a wildcard ("image/*") or a
  # MIME type ("application/pdf").
  def file_type_matches?(blob, type)
    if type.start_with?(".")
      blob.filename.extension_with_delimiter.casecmp?(type) && content_fits_extension?(blob.content_type.to_s, type)
    elsif type.end_with?("/*")
      blob.content_type.to_s.downcase.start_with?(type.delete_suffix("*").downcase)
    else
      blob.content_type.to_s.casecmp?(type)
    end
  end

  # A program or picture named invoice.pdf is identified as what it is, so it
  # is not a .pdf. Only the name can tell an extension Marcel does not know,
  # or a format it has no signature for inside a bare Office or zip container
  # (an Outlook .msg).
  def content_fits_extension?(content_type, extension)
    named = Marcel::MimeType.for(extension: extension.downcase)
    return true if named == Marcel::MimeType::BINARY || Marcel::Magic.child?(content_type, named)

    CONTAINER_TYPES.include?(content_type) && Marcel::MAGIC.none? { |type, _| type == named }
  end

  def purge_file_attachments
    ActiveStorage::Attachment.where(record_type: EntityEntry.polymorphic_name, record_id: id).includes(:blob).each(&:purge_later)
  end
end
