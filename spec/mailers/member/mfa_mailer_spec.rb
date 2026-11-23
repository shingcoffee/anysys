# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::MfaMailer do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, :with_mfa, customer: customer) }
  let(:token)    { "signed-token-fixture" }

  describe "#reset_link" do
    let(:mail) { described_class.with(user: user, token: token).reset_link }

    it "is addressed to the user" do
      expect(mail.to).to eq([user.email])
    end

    it "has the expected subject" do
      expect(mail.subject).to match(/two-factor authentication/i)
    end

    it "includes the consume URL with the token" do
      expect(mail.body.encoded).to include(
        "/#{customer.id}/auth/mfa_recovery/consume"
      )
      expect(mail.body.encoded).to include(token)
    end

    it "warns about the 15-minute expiry" do
      expect(mail.body.encoded).to match(/15 minutes/i)
    end

    it "renders branded HTML chrome around the consume link" do
      html = mail.html_part.body.to_s

      expect(html).to include(I18n.t("member.mfa_mailer.reset_link.heading"))
      expect(html).to include(I18n.t("member.mfa_mailer.reset_link.title"))
      expect(html).to include(I18n.t("member.mfa_mailer.reset_link.disable_link"))
      expect(html).to include(I18n.t("member.mfa_mailer.reset_link.brand"))
    end
  end
end
