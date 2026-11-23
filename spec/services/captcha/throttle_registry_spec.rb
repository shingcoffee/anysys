# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captcha::ThrottleRegistry do
  let_it_be(:customer) { create(:customer) }

  after { described_class.bust! }

  describe ".page_index" do
    it "indexes pages that include the public audience, including public-only pages" do
      described_class.bust!
      public_only = create(:page, :public_only, :launched, customer: customer)
      all_three = create(:page, :for_member, :for_public, :launched, customer: customer)
      member_only = create(:page, :member_only, :launched, customer: customer)
      admin_only = create(:page, :launched, customer: customer)

      index = described_class.page_index

      expect(index.keys).to include(public_only.public_uuid.to_s, all_three.public_uuid.to_s)
      expect(index.keys).not_to include(member_only.public_uuid.to_s, admin_only.public_uuid.to_s)
    end
  end
end
