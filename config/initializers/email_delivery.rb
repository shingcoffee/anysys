# frozen_string_literal: true

# DKIM signing interceptor for SMTP-provider mail, scoped by the X-Anysys-Mode
# header set in Emails::DeliveryMailer, so it no-ops on all other app mail.
# Delivery status + retries are owned by Emails::DeliverMessageJob (which calls
# the mailer via deliver_now), so no observer or MailDeliveryJob.retry_on here.
Rails.application.config.to_prepare do
  ActionMailer::Base.register_interceptor(Emails::DkimInterceptor)
end
