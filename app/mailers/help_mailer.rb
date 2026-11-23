# frozen_string_literal: true

class HelpMailer < ApplicationMailer
  SUPPORT_TO = "help@anysys.com"

  def support_request(customer:, user:, subject:, body:, page_url:, files: [])
    @customer = customer
    @user = user
    @request_body = body
    @page_url = page_url
    @subject_line = subject

    Array(files).each do |file|
      attachments[file[:filename].presence || "attachment"] = {
        mime_type: file[:content_type],
        content: file[:content]
      }
    end

    mail(
      to: SUPPORT_TO,
      from: Devise.mailer_sender,
      reply_to: user.email,
      subject: t("help_mailer.support_request.subject", subject: subject)
    )
  end
end
