# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::Audience::List, type: :model do
  describe "validations" do
    it "requires customer_id" do
      list = build(:email_list, customer: nil)
      Current.customer = nil
      expect(list).not_to be_valid
    end

    it "requires name" do
      list = build(:email_list, name: nil)
      expect(list).not_to be_valid
    end

    it "does not define an active scope" do
      expect(described_class).not_to respond_to(:active)
    end
  end

  describe "#audience and #audience_count" do
    it "resolves its audience via AudienceQuery" do
      customer = create(:customer)
      ada = create(:user, customer: customer, first_name: "Ada")
      create(:user, customer: customer, first_name: "Bob")
      list = create(:email_list, :dynamic, customer: customer)
      expect(list.audience.to_a).to eq([ada])
      expect(list.audience_count).to eq(1)
    end
  end
end
