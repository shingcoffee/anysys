# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Notifications do
  let(:customer) { create(:customer) }
  let(:other) { create(:customer) }
  let(:user) { create(:user, :member, customer: customer) }
  let(:ctx) { { customer_id: customer.id, current_user_id: user.id, errors: [] } }
  let(:title) { { "en" => "Notice" } }
  let(:body) { { "en" => "Your request was received." } }

  it "creates a notification for a same-customer recipient" do
    expect(described_class.create(ctx, recipient: user.id, title: title, body: body)).to be(true)
    row = FlowchartNotification.find_by!(customer_id: customer.id, user_id: user.id)
    expect(row.title).to eq("en" => "Notice")
    expect(row.body).to eq("en" => "Your request was received.")
    expect(row.page_id).to be_nil
  end

  it "creates notifications for every same-customer recipient" do
    peer = create(:user, :member, customer: customer)
    expect(described_class.create(ctx, recipient: [user.id, peer.id], title: title, body: body)).to be(true)
    expect(FlowchartNotification.where(customer_id: customer.id).pluck(:user_id)).to contain_exactly(user.id, peer.id)
  end

  it "fails when the recipient belongs to another tenant" do
    stranger = create(:user, :member, customer: other)
    expect(described_class.create(ctx, recipient: stranger.id, title: title, body: body)).to be(false)
    expect(ctx[:errors]).to include(I18n.t("flowchart_runtime.errors.create_notification.recipient_not_found"))
    expect(FlowchartNotification.where(customer_id: customer.id)).to be_empty
  end

  it "attaches a launched same-customer or shared page and refuses a foreign page" do
    allow_any_instance_of(Page).to receive(:bind_default_flowchart)
    page = create(:page, customer: customer, launched: true)
    shared = create(:page, :shared, launched: true)
    foreign = create(:page, customer: other, launched: true)

    expect(described_class.create(ctx, recipient: user.id, title: title, body: body, page_id: page.id)).to be(true)
    expect(described_class.create(ctx, recipient: user.id, title: title, body: body, page_id: shared.id)).to be(true)
    expect(described_class.create(ctx.merge(errors: []), recipient: user.id, title: title, body: body, page_id: foreign.id)).to be(false)

    pages = FlowchartNotification.where(customer_id: customer.id, user_id: user.id).pluck(:page_id)
    expect(pages).to include(page.id, shared.id)
    expect(pages).not_to include(foreign.id)
  end

  it "notifies a duplicated recipient only once" do
    expect(described_class.create(ctx, recipient: [user.id, user.id.to_s], title: title, body: body)).to be(true)
    expect(FlowchartNotification.where(customer_id: customer.id, user_id: user.id).count).to eq(1)
  end

  it "rolls the row back with the surrounding transaction" do
    FlowchartNotification.transaction do
      described_class.create(ctx, recipient: user.id, title: title, body: body)
      raise ActiveRecord::Rollback
    end
    expect(FlowchartNotification.where(customer_id: customer.id)).to be_empty
  end

  it "raises when customer_id is missing" do
    expect { described_class.create({}, recipient: user.id, title: title, body: body) }
      .to raise_error(FlowchartRuntime::Notifications::Error, /customer_id/)
  end
end
