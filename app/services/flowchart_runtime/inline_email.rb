# frozen_string_literal: true

module FlowchartRuntime
  # Sends an email written in the step itself (send_email): recipients,
  # subject and body arrive already rendered, so processing needs no email
  # template set up first. A notification that cannot go out leaves the
  # submission alone unless the step asks to fail it.
  module InlineEmail
    class Error < StandardError; end

    ON_ERRORS = %w[continue fail].freeze

    module_function

    # One message per recipient; returns their ids, [] when a "continue"
    # send failed, or false once it failed the run.
    def deliver(ctx, to:, subject:, body:, cc: "", bcc: "", reply_to: "", on_error: "continue",
                locale: nil, attachments: nil, idempotency_key: nil)
      chosen = locale.presence || ctx[:locale].presence || I18n.locale
      I18n.with_locale(chosen) { dispatch(ctx, to:, subject:, body:, cc:, bcc:, reply_to:, attachments:, idempotency_key:) }
    rescue Error, Email::Errors::Error => error
      return Step.attempt(ctx, :"send_email.failed", error.class) { raise error } if on_error.to_s == "fail"

      Rails.logger.warn("[FlowchartRuntime::InlineEmail] #{error.class}: #{error.message}")
      []
    end

    def dispatch(ctx, to:, subject:, body:, cc:, bcc:, reply_to:, attachments:, idempotency_key:)
      recipients = addresses(to)
      raise Error, "no valid recipient in #{to.inspect}" if recipients.empty?

      customer = Customer.find_by(id: ctx[:customer_id])
      text = body.to_s.strip
      html = ERB::Util.html_escape(text).gsub(/\r?\n/, "<br>\n")
      blob_ids = blob_ids_from(attachments, customer&.id)
      recipients.map do |address|
        Emails::Gateway.send_raw(
          customer: customer,
          to: address,
          subject: subject.to_s.squish,
          body_html: html,
          body_text: text,
          cc: addresses(cc).join(", ").presence,
          bcc: addresses(bcc).join(", ").presence,
          reply_to: addresses(reply_to).first,
          attachment_blob_ids: blob_ids,
          idempotency_key: idempotency_key
        )&.id
      end
    end

    def addresses(list)
      parts = list.is_a?(Array) ? list : list.to_s.split(/[,;\s]+/)
      parts.map(&:to_s).map(&:strip).select { |address| address.match?(URI::MailTo::EMAIL_REGEXP) }.uniq
    end

    # Accepts a generate_document result hash, an in-memory file (the
    # FilePayload shape generate_file and download_file produce, stored here
    # as a blob of the run's customer), an array of those, or blob ids;
    # delivery still scopes blobs with for_customer.
    def blob_ids_from(value, customer_id)
      attachment_items(value).filter_map do |item|
        case item
        when ActiveStorage::Blob then item.id
        when ActiveStorage::Attachment then item.blob_id
        when Hash
          item["blob_id"] || item[:blob_id] || item["id"] || item[:id] || stored_blob_id(item, customer_id)
        when Integer
          item
        else
          Integer(item.to_s, exception: false)
        end
      end
    end

    # A record's File or Image field (model.contract) attaches the files it holds.
    def attachment_items(value)
      case value
      when nil then []
      when Hash then [value]
      when ActiveStorage::Attached::One then value.attached? ? [value.blob] : []
      when ActiveStorage::Attached::Many then value.blobs.to_a
      else Array(value).flat_map { |item| item.is_a?(ActiveStorage::Attached) ? attachment_items(item) : [item] }
      end
    end

    def stored_blob_id(item, customer_id)
      return unless %w[content data body].any? { |key| item.key?(key) || item.key?(key.to_sym) }

      file = FilePayload.extract(item)
      return if file[:content].empty?

      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(file[:content]),
        filename: file[:filename] || "attachment.bin",
        content_type: file[:content_type] || FilePayload.sniff(file[:content], filename: file[:filename]),
        metadata: { "customer_id" => customer_id }.compact
      )
      blob.update_column(:customer_id, customer_id) if customer_id && blob.customer_id != customer_id
      blob.id
    end
    private_class_method :dispatch, :addresses, :blob_ids_from, :attachment_items, :stored_blob_id
  end
end
