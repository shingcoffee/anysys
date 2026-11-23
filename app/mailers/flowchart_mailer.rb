# frozen_string_literal: true

# ActionMailer needs a named action to rebuild the message inside its delivery
# job. Keep MIME construction here so generated steps only pass serializable
# values and never mutate a lazily processed MessageDelivery before enqueueing.
class FlowchartMailer < ApplicationMailer
  layout false

  def notification(to:, subject:, body: "", html_part: nil, text_part: nil,
                   attachments: {}, headers: {}, priority: nil, **recipients)
    attachments.each { |filename, content| self.attachments[filename] = content }
    self.headers(FlowchartRuntime::MailHeaders.fields(headers))
    self.headers["X-Priority"] = FlowchartRuntime::MailHeaders.unstructured(priority) if priority

    options = FlowchartRuntime::MailHeaders.recipients(recipients).merge(
      to: FlowchartRuntime::MailHeaders.addresses!(to),
      subject: FlowchartRuntime::MailHeaders.unstructured(subject)
    )
    if html_part || text_part
      mail(**options) do |format|
        format.text { render plain: text_part } unless text_part.nil?
        format.html { render html: html_part.html_safe } unless html_part.nil?
      end
    else
      mail(**options) do |format|
        format.text { render plain: body }
      end
    end
  end
end
