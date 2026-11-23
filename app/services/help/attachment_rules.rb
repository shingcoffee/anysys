# frozen_string_literal: true

module Help
  module AttachmentRules
    IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
    EMAIL_TYPES = (IMAGE_TYPES + %w[application/pdf]).freeze
    MAX_FILES = 5
    MAX_BYTES = 5.megabytes

    module_function

    def image_accept = IMAGE_TYPES.join(",")
    def email_accept = EMAIL_TYPES.join(",")
    def size_label = I18n.t("help.errors.file_size_label")

    def normalize(files)
      Array(files).flatten.compact_blank
    end

    def attach_images!(record, files)
      normalize(files).each { |upload| record.images.attach(upload) }
    end

    def validate(files, allowed_types:, errors:, attribute:)
      list = normalize(files)
      if list.size > MAX_FILES
        errors.add(attribute, I18n.t("help.errors.too_many_files", count: MAX_FILES))
        return
      end

      list.each do |file|
        type = content_type_for(file)
        size = byte_size_for(file)
        unless allowed_types.include?(type)
          errors.add(attribute, I18n.t("help.errors.invalid_file_type"))
          break
        end
        if size.nil? || size > MAX_BYTES
          errors.add(attribute, I18n.t("help.errors.file_too_large", size: size_label))
          break
        end
      end
    end

    def stimulus_data(accept:)
      {
        controller: "help-attachments",
        help_attachments_max_files_value: MAX_FILES,
        help_attachments_max_bytes_value: MAX_BYTES,
        help_attachments_accept_value: accept,
        help_attachments_too_many_template_value: I18n.t("chrome.help_menu.errors.too_many"),
        help_attachments_type_label_value: I18n.t("chrome.help_menu.errors.type"),
        help_attachments_size_template_value: I18n.t("chrome.help_menu.errors.size"),
        help_attachments_size_label_value: size_label,
        help_attachments_remove_label_value: I18n.t("chrome.help_menu.errors.remove"),
        help_attachments_remove_mark_value: I18n.t("chrome.help_menu.errors.remove_mark")
      }
    end

    def content_type_for(file)
      return file.content_type.to_s if file.respond_to?(:content_type)

      nil
    end

    def byte_size_for(file)
      return file.size if file.respond_to?(:size)
      return file.byte_size if file.respond_to?(:byte_size)

      nil
    end
  end
end
