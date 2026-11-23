# frozen_string_literal: true

require "rails_helper"

RSpec.describe Help::Activities::CreateRequest do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }

  it "creates a ticket with a requester message and marks it read for the author" do
    result = described_class.call(
      customer: customer,
      user: admin,
      params: { subject: "Cannot save", body: "The save button does nothing." }
    )

    expect(result.success?).to be true
    expect(result.model).to be_persisted
    expect(result.model).to have_attributes(subject: "Cannot save", status: "open", user_id: admin.id, customer_id: customer.id)
    expect(result.model.messages.sole).to have_attributes(author_role: "requester", body: "The save button does nothing.")
    expect(SupportTicketRead.last_read_at_for(user_id: admin.id, support_ticket_id: result.model.id)).to be_present
  end

  it "attaches images to the first message" do
    result = described_class.call(
      customer: customer,
      user: admin,
      params: { subject: "Screenshot", body: "See attached.", images: [ png_upload ] }
    )

    expect(result.success?).to be true
    expect(result.model.messages.sole.images).to be_attached
  end

  it "attaches every image from a multi-file upload" do
    result = described_class.call(
      customer: customer,
      user: admin,
      params: {
        subject: "Screenshots",
        body: "See attached.",
        images: [ png_upload("one.png"), png_upload("two.png") ]
      }
    )

    expect(result.success?).to be true
    expect(result.model.messages.sole.images.count).to eq(2)
  end

  it "rejects a blank subject" do
    result = described_class.call(customer: customer, user: admin, params: { subject: "", body: "Hello" })

    expect(result.success?).to be false
    expect(result.errors).to have_key(:subject)
    expect(SupportTicket.count).to eq(0)
  end

  it "rejects a disallowed image type" do
    result = described_class.call(
      customer: customer,
      user: admin,
      params: { subject: "Bad file", body: "See attached.", images: [ txt_upload ] }
    )

    expect(result.success?).to be false
    expect(result.errors).to have_key(:images)
  end
end
