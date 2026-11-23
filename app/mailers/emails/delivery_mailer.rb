# frozen_string_literal: true

module Emails
  # Pure-ActionMailer transport for the Email + Email Campaign modules.
  #
  # The Emails::Message ledger row is ALREADY rendered upstream
  # (Emails::TemplateRenderer): subject/body_html/body_text/envelope are stored.
  # This mailer does NO content rendering — it emits the stored strings verbatim
  # (layout false, so body_html is the html part as-is, matching the retired
  # Email::Adapters::Smtp). Per-mode DB SMTP credentials are passed natively via
  # delivery_method_options:. X-Anysys-* headers scope the interceptor/observer
  # to this module's mail only.
  class DeliveryMailer < ApplicationMailer
    layout false

    # Status is owned by Emails::DeliverMessageJob (which invokes this mailer via
    # the SMTP provider with deliver_now); a raise here propagates to the job's
    # retry/dead-letter handling. This mailer is a pure transport.

    # message_id + mode + the queued transport's credential_id arrive via `.with(...)`.
    def deliver_email
      @message = Emails::Message.find_by(id: params[:message_id])
      return if @message.nil?

      mode       = params[:mode] || Email::CredentialResolver.default_mode
      # This mailer is the SMTP transport; always resolve the SMTP credential
      # (not merely the default provider, which another vendor could claim).
      credential = if params[:credential_id].present?
                     Email::CredentialResolver.for_recorded(credential_id: params[:credential_id], mode: mode, provider: "smtp")
                   else
                     Email::CredentialResolver.call(mode: mode, provider: "smtp")
                   end

      attach_inline_blobs(@message)

      headers["X-Anysys-Message-Id"]    = @message.id.to_s
      headers["X-Anysys-Mode"]          = mode
      headers["X-Anysys-Credential-Id"] = credential.id.to_s
      stamp_unsubscribe_headers(@message)

      message_record = @message
      mail(
        to:                      message_record.to,
        from:                    message_record.from,
        cc:                      message_record.cc.presence,
        bcc:                     message_record.bcc.presence,
        reply_to:                message_record.reply_to.presence,
        subject:                 message_record.subject,
        delivery_method_options: smtp_settings(credential)
      ) do |format|
        format.text { render plain: message_record.body_text.to_s }
        format.html { render html: message_record.body_html.to_s.html_safe }
      end
    end

    private

    # RFC 8058 one-click unsubscribe headers — required by Gmail/Yahoo bulk
    # sender rules for campaign (bulk) mail. Transactional mail is exempt.
    # The URL targets the existing signed-token route, whose POST action
    # unsubscribes without further interaction.
    def stamp_unsubscribe_headers(message)
      Email::MimeMessage.unsubscribe_headers(message).each { |name, value| headers[name] = value }
    end

    def attach_inline_blobs(message)
      ids = message.metadata&.dig("attachment_blob_ids") || []
      return if ids.empty?

      blobs = ActiveStorage::Blob.for_customer(message.customer_id).where(id: ids).index_by(&:id)
      ids.each do |id|
        blob = blobs[id] || blobs[id.to_i]
        next unless blob

        name = "blob-#{id}"
        attachments.inline[name] = { mime_type: blob.content_type, content: blob.download }
        attachments[name].content_id = "<blob-#{id}>"
      end
    end

    def smtp_settings(credential)
      {
        address:              credential.host,
        port:                 credential.port,
        user_name:            credential.username,
        password:             credential.password,
        authentication:       credential.authentication.to_sym,
        enable_starttls_auto: credential.enable_starttls,
        ssl:                  credential.ssl,
        domain:               credential.domain
      }.compact
    end
  end
end
