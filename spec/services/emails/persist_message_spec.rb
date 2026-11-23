require "rails_helper"

RSpec.describe Emails::PersistMessage do
  let(:customer) { create(:customer) }

  it "creates a queued message" do
    message, created = described_class.call({
      customer: customer,
      to: "test@example.com",
      from: "sender@example.com",
      subject: "Hi",
      body_html: "<p>Hi</p>",
      body_text: "Hi",
      message_type: "transactional",
      status: "queued",
      provider: "smtp"
    })
    expect(created).to be true
    expect(message).to be_persisted
    expect(message.status).to eq("queued")
  end

  it "returns existing row on idempotency race" do
    attrs = {
      customer: customer, to: "test@example.com", from: "sender@example.com", subject: "Hi",
      body_html: "<p>Hi</p>", body_text: "Hi",
      message_type: "transactional", status: "queued", provider: "smtp",
      idempotency_key: "abc"
    }
    first, first_created = described_class.call(attrs)
    second, second_created = described_class.call(attrs)
    expect(first_created).to be true
    expect(second_created).to be false
    expect(second.id).to eq(first.id)
  end

  it "handles ActiveRecord::RecordNotUnique by returning existing row" do
    attrs = {
      customer: customer, to: "test@example.com", from: "sender@example.com", subject: "Hi",
      body_html: "<p>Hi</p>", body_text: "Hi",
      message_type: "transactional", status: "queued", provider: "smtp",
      idempotency_key: "def"
    }
    existing = Emails::Message.create!(attrs)

    allow_any_instance_of(described_class).to receive(:existing_message).and_return(nil, existing)

    # Simulate DB-level race condition where AR validation passes but DB raises
    allow(Emails::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    message, created = described_class.call(attrs, idempotency_key: "def")
    expect(created).to be false
    expect(message.id).to eq(existing.id)
  end

  it "reloads the actual database winner after a real unique-index rejection" do
    attrs = {
      customer: customer, to: "test@example.com", from: "sender@example.com", subject: "Hi",
      body_html: "<p>Hi</p>", message_type: "transactional", status: "queued", provider: "smtp",
      idempotency_key: "real-index-race"
    }
    existing = Emails::Message.create!(attrs)
    service = described_class.new(attrs)
    reads = 0
    allow(service).to receive(:existing_message).and_wrap_original do |method|
      reads += 1
      reads == 1 ? nil : method.call
    end
    # Bypass the advisory AR uniqueness check to exercise the actual DB index.
    allow_any_instance_of(Emails::Message).to receive(:valid?).and_return(true)

    expect {
      message, created = service.call
      expect(message.id).to eq(existing.id)
      expect(created).to be(false)
    }.not_to change(Emails::Message, :count)
    expect(reads).to eq(2)
  end

  it "does not recover an unrelated validation error even when the idempotency key has a winner" do
    attrs = {
      customer: customer, to: "test@example.com", from: "sender@example.com", subject: "Hi",
      body_html: "<p>Hi</p>", idempotency_key: "validation-race"
    }
    Emails::Message.create!(attrs)
    service = described_class.new(attrs)
    allow(service).to receive(:existing_message).and_return(nil)
    invalid = Emails::Message.new(attrs)
    invalid.errors.add(:idempotency_key, :invalid)
    allow(Emails::Message).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

    expect { service.call }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "re-raises a uniqueness failure without a same-tenant, same-key winner" do
    create(:email_message, customer: create(:customer), idempotency_key: "foreign-winner")
    attrs = {
      customer: customer, to: "test@example.com", from: "sender@example.com", subject: "Hi",
      body_html: "<p>Hi</p>", idempotency_key: "foreign-winner"
    }
    allow(Emails::Message).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, "unrelated unique index")

    expect { described_class.call(attrs) }.to raise_error(ActiveRecord::RecordNotUnique, "unrelated unique index")
  end
end
