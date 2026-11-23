# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Analytics::ExportCsv do
  let(:customer) { create(:customer) }

  describe ".call" do
    it "exports message rows as CSV" do
      message = create(:email_message, customer: customer, status: "delivered",
                                       to: "user@example.com", subject: "Hello",
                                       sent_at: 1.day.ago, delivered_at: 1.day.ago)
      Emails::MessageEvent.create!(message: message, event_type: "open", occurred_at: 1.day.ago)
      Emails::MessageEvent.create!(message: message, event_type: "click", occurred_at: 1.day.ago)

      csv = described_class.call(Emails::Message.where(customer_id: customer.id))
      rows = CSV.parse(csv, headers: true)

      expect(rows.size).to eq(1)
      row = rows.first
      expect(row["id"].to_i).to eq(message.id)
      expect(row["to"]).to eq("user@example.com")
      expect(row["subject"]).to eq("Hello")
      expect(row["status"]).to eq("delivered")
      expect(row["opened"].to_i).to eq(1)
      expect(row["clicked"].to_i).to eq(1)
    end

    it "returns only headers when no messages match" do
      csv = described_class.call(Emails::Message.where(customer_id: customer.id))
      rows = CSV.parse(csv, headers: true)

      expect(rows.size).to eq(0)
      expect(rows.headers).to eq(%w[id to subject status sent_at delivered_at opened clicked])
    end

    it "does not dump every matching message" do
      stub_const("#{described_class}::MAX_ROWS", 2)
      create(:email_message, customer: customer, to: "aaa@example.com", created_at: 3.days.ago)
      create(:email_message, customer: customer, to: "bbb@example.com", created_at: 2.days.ago)
      create(:email_message, customer: customer, to: "ccc@example.com", created_at: 1.day.ago)

      csv = described_class.call(Emails::Message.where(customer_id: customer.id))

      expect(csv).to include("ccc@example.com")
      expect(csv).to include("bbb@example.com")
      expect(csv).not_to include("aaa@example.com")
    end
  end
end
