# frozen_string_literal: true

require "rails_helper"

RSpec.describe Help::Activities::SendEmail do
  let(:customer) { create(:customer, name: "Acme") }
  let(:admin) { create(:user, :admin, customer: customer, first_name: "Ada", last_name: "Admin") }

  it "delivers to help@anysys.com with Reply-To the requester" do
    result = described_class.call(
      customer: customer,
      user: admin,
      params: { subject: "Need access", body: "Please enable the module.", page_url: "https://app.anysys.com/x" }
    )

    expect(result.success?).to be true
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ "help@anysys.com" ])
    expect(mail.reply_to).to eq([ admin.email ])
    expect(mail.subject).to include("Need access")
    expect(mail.body.encoded).to include("Please enable the module.")
    expect(mail.body.encoded).to include("Acme")
  end

  it "rejects a blank body" do
    result = described_class.call(customer: customer, user: admin, params: { subject: "Hi", body: "" })

    expect(result.success?).to be false
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "returns a failure instead of raising when delivery fails" do
    mailer = instance_double(ActionMailer::MessageDelivery)
    allow(HelpMailer).to receive(:support_request).and_return(mailer)
    allow(mailer).to receive(:deliver_now).and_raise(IOError, "connection reset")

    result = described_class.call(
      customer: customer,
      user: admin,
      params: { subject: "Need access", body: "Please enable the module." }
    )

    expect(result.success?).to be false
    expect(result.messages).to eq([ "The help email could not be sent. Please try again later." ])
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "returns a failure for SocketError instead of raising" do
    mailer = instance_double(ActionMailer::MessageDelivery)
    allow(HelpMailer).to receive(:support_request).and_return(mailer)
    allow(mailer).to receive(:deliver_now).and_raise(SocketError, "getaddrinfo")

    result = described_class.call(
      customer: customer,
      user: admin,
      params: { subject: "Need access", body: "Please enable the module." }
    )

    expect(result.success?).to be false
    expect(result.messages).to eq([ I18n.t("help.flash.email_failed") ])
  end
end
