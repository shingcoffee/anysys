# frozen_string_literal: true

require "net/smtp"
require "timeout"

module Help
  module Activities
    class SendEmail
      def self.call(customer:, user:, params:)
        attributes = sanitize(params)
        contract = Help::Contracts::Email.new(SupportTicket.new)
        unless contract.validate(attributes)
          return Help::Result.new(success?: false, model: nil,
                                   errors: contract.errors.messages.to_h,
                                   messages: contract.errors.full_messages)
        end

        files = Help::AttachmentRules.normalize(attributes[:attachments]).map { |upload| snapshot(upload) }
        begin
          HelpMailer.support_request(
            customer: customer,
            user: user,
            subject: attributes[:subject].to_s.strip,
            body: attributes[:body].to_s.strip,
            page_url: attributes[:page_url].to_s.presence,
            files: files
          ).deliver_now
        rescue StandardError => e
          Rails.logger.warn("[Help::SendEmail] delivery failed: #{e.class}: #{e.message}")
          return Help::Result.new(success?: false, model: nil, errors: {},
                                  messages: [I18n.t("help.flash.email_failed")])
        end

        Help::Result.new(success?: true, model: nil, errors: {}, messages: [])
      end

      def self.sanitize(params)
        params.to_h.symbolize_keys.slice(:subject, :body, :attachments, :page_url)
      end
      private_class_method :sanitize

      # ActionMailer deliver_later cannot serialize an UploadedFile. Capture
      # bytes + metadata before the request IO is closed.
      def self.snapshot(upload)
        bytes = if upload.respond_to?(:read)
          data = upload.read
          upload.rewind if upload.respond_to?(:rewind)
          data
        else
          upload.download
        end
        {
          filename: upload.respond_to?(:original_filename) ? upload.original_filename : upload.filename.to_s,
          content_type: Help::AttachmentRules.content_type_for(upload),
          content: bytes
        }
      end
      private_class_method :snapshot
    end
  end
end
