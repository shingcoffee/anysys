# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiAssistant::Activities::UndoWebsiteReply do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user) { create(:user, :admin, customer: customer) }
  let(:conversation) { create(:ai_assistant_conversation, customer: customer, user: user) }
  let!(:website) { create(:website, customer: customer) }
  let!(:page) { create(:website_page, website: website, customer: customer, title: "Menu", slug: "menu", position: 1) }
  let(:reply) do
    entry = Websites::Assistant::Undo.entry(page)
    create(:ai_assistant_message, :assistant, conversation: conversation, customer: customer,
      metadata: { "changes" => [], Websites::Assistant::Undo::KEY => { "pages" => [ entry ] } })
  end

  before do
    enable_ai_assistant!(customer)
    enable_module!("website", customer)
    allow(AiAssistant::Stream).to receive(:broadcast_message_replace)
    allow(AiAssistant::Stream).to receive(:broadcast_artifact)
  end

  def call(user: self.user, customer: self.customer, message_id: reply.id)
    described_class.call(customer: customer, user: user, message_id: message_id)
  end

  it "undoes the reply and redraws it and the preview pane" do
    result = call

    expect(result).to have_attributes(success?: true, http_status: 200, message: reply)
    expect(WebsitePage.exists?(page.id)).to be(false)
    expect(AiAssistant::Stream).to have_received(:broadcast_message_replace).with(reply)
    expect(AiAssistant::Stream).to have_received(:broadcast_artifact).with(conversation)
  end

  it "undoes under the conversation's lock, so it cannot interleave with a reply being written" do
    reply
    expect_any_instance_of(AiAssistant::Conversation).to receive(:with_lock).and_call_original

    expect(call.success?).to be(true)
  end

  it "reports the committed undo even when the redraw fails" do
    allow(AiAssistant::Stream).to receive(:broadcast_message_replace).and_raise("cable down")
    allow(Rails.logger).to receive(:error)

    expect(call).to have_attributes(success?: true, http_status: 200)
    expect(WebsitePage.exists?(page.id)).to be(false)
    expect(Rails.logger).to have_received(:error).with(a_string_including("cable down"))
  end

  it "renders the redrawn reply outside a request, where a render error would only be logged" do
    allow(AiAssistant::Stream).to receive(:broadcast_message_replace).and_call_original
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    call

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
      anything,
      hash_including(target: "ai_assistant_message_#{reply.id}", html: a_string_including(I18n.t("ai_assistant.assistant.website.undo.done")))
    )
  end

  it "returns the reply with the refusal when a page changed since" do
    reply
    page.update!(title: "Menu (edited)")

    result = call

    expect(result).to have_attributes(success?: false, http_status: 422, message: reply)
    expect(result.errors).to eq([ I18n.t("ai_assistant.assistant.website.undo.errors.changed", title: "Menu (edited)") ])
    expect(AiAssistant::Stream).not_to have_received(:broadcast_message_replace)
  end

  it "does not reach a reply in another admin's conversation" do
    other = create(:user, :admin, customer: customer)

    expect(call(user: other)).to have_attributes(success?: false, http_status: 404, message: nil)
    expect(WebsitePage.exists?(page.id)).to be(true)
  end

  it "does not reach a reply from another tenant" do
    other_customer = create(:customer)
    other_admin = create(:user, :admin, customer: other_customer)
    enable_ai_assistant_module!(other_customer)
    enable_module!("website", other_customer)

    expect(call(user: other_admin, customer: other_customer)).to have_attributes(http_status: 404, message: nil)
    expect(WebsitePage.exists?(page.id)).to be(true)
  end

  it "does not undo a user message" do
    user_message = create(:ai_assistant_message, conversation: conversation, customer: customer)

    expect(call(message_id: user_message.id).http_status).to eq(404)
  end

  it "refuses while the Website module is off" do
    reply
    allow(FeatureModules::Website::Registration).to receive(:enabled_for?).with(customer.id).and_return(false)

    expect(call).to have_attributes(success?: false, http_status: 403)
    expect(WebsitePage.exists?(page.id)).to be(true)
  end
end
