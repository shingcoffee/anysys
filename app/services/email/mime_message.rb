# frozen_string_literal: true

require "mail"

module Email
  # Mail owns MIME boundaries, encodings and inline attachment packaging. SES
  # Raw content uses this builder rather than dropping compiled cid: images.
  class MimeMessage
    def self.call(message:)
      mail = Mail.new
      %i[to from cc bcc reply_to subject].each do |field|
        value = message.public_send(field)
        mail.public_send("#{field}=", value) if value.present?
      end
      unsubscribe_headers(message).each { |name, value| mail[name] = value }

      ids = Array(message.metadata&.dig("attachment_blob_ids"))
      blobs = ActiveStorage::Blob.for_customer(message.customer_id).where(id: ids).to_a
      content = blobs.any? ? Mail::Part.new : mail
      content.text_part = part(message.body_text, "text/plain") if message.body_text.present?
      content.html_part = part(message.body_html, "text/html")
      if blobs.any?
        mail.content_type = "multipart/related"
        mail.add_part(content)
      end
      blobs.each do |blob|
        name = "blob-#{blob.id}"
        mail.attachments.inline[name] = { mime_type: blob.content_type, content: blob.download }
        mail.attachments[name].content_id = "<#{name}>"
      end
      # Bcc remains in SES's explicit destination envelope, never in raw headers.
      mail.header["Bcc"] = nil
      mail
    end

    def self.unsubscribe_headers(message)
      return {} unless message.message_type.to_s == "campaign"

      url = Emails::SendActivities::SendActivityUnsubscribe.url_for_message(message)
      return {} if url.blank?

      { "List-Unsubscribe" => "<#{url}>", "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click" }
    end

    def self.part(body, content_type)
      Mail::Part.new(content_type: "#{content_type}; charset=UTF-8", body: body.to_s)
    end
    private_class_method :part
  end
end
