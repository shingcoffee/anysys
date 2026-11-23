require 'rails_helper'

RSpec.describe Emails::MessageEvent, type: :model do
  describe "validations" do
    it "validates event_type" do
      event = described_class.new(event_type: "invalid")
      expect(event.valid?).to be false
    end
  end

  describe ".record_open!" do
    it "creates an open event" do
      message = create(:email_message)
      expect {
        described_class.record_open!(message, request: ActionDispatch::TestRequest.create)
      }.to change(described_class, :count).by(1)
    end
  end

  describe ".record_click!" do
    it "creates a click event" do
      message = create(:email_message)
      expect {
        described_class.record_click!(message, url: "https://example.com", request: ActionDispatch::TestRequest.create)
      }.to change(described_class, :count).by(1)
    end

    it "truncates a click URL longer than 255 characters" do
      message = create(:email_message)
      url = "https://example.com/" + ("a" * 300)
      described_class.record_click!(message, url: url, request: ActionDispatch::TestRequest.create)
      expect(described_class.last.url.length).to eq(255)
    end
  end
end
