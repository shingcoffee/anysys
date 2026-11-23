# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::TemplateEmail do
  let(:customer) { create(:customer) }
  let!(:template) do
    create(
      :email_template,
      customer: customer,
      name: "welcome",
      subject: "Hi #{platform_token('first_name')}",
      body_html: "<p>Hello #{platform_token('first_name')}</p>"
    )
  end
  let!(:credential) { create(:email_credential, mode: "sandbox") }
  let(:ctx) { { customer_id: customer.id, errors: [] } }

  before { allow(Emails::DeliverMessageJob).to receive(:perform_later) }

  it "sends through the gateway for the run's customer and returns the message id" do
    id = described_class.deliver(ctx, to: "user@example.test", template_id: template.id, vars: { "first_name" => "Ada" })

    message = Emails::Message.last
    expect(id).to eq(message.id)
    expect(message).to have_attributes(customer_id: customer.id, to: "user@example.test", email_template_id: template.id)
  end

  it "renders inside the given locale" do
    seen = nil
    allow(I18n).to receive(:with_locale).and_wrap_original do |original, locale, &block|
      seen = locale
      original.call(locale, &block)
    end

    described_class.deliver(ctx, to: "user@example.test", template_id: template.id, vars: { "first_name" => "Ada" },
                                 locale: "zh-CN")
    expect(seen.to_s).to eq("zh-CN")
  end
end
