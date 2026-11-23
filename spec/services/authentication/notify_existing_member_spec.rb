# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::NotifyExistingMember do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }

  before { Authentication::Throttle.reset_store! }
  after { Authentication::Throttle.reset_store! }

  it "issues a sign-in link to a confirmed active member of the tenant" do
    member = create(:user, :member, customer: customer, email: "member@example.com")
    expect(Authentication::IssueSignInLink).to receive(:call).with(email: member.email)

    expect(described_class.call(user: member, customer_id: customer.id)).to be(true)
  end

  it "does nothing for an unconfirmed member, an admin, another tenant's member, or nobody" do
    expect(Authentication::IssueSignInLink).not_to receive(:call)
    users = [
      create(:user, :member, :unconfirmed, customer: customer),
      create(:user, :admin, customer: customer),
      create(:user, :member, customer: other_customer),
      nil
    ]

    users.each do |user|
      expect(described_class.member_of?(user, customer.id)).to be(false)
      expect(described_class.call(user: user, customer_id: customer.id)).to be(false)
    end
  end

  it "shares the sign-in link page's per-address flood bucket" do
    member = create(:user, :member, customer: customer, email: "member@example.com")
    limit = Authentication::EmailFloodThrottled::DEFAULT_LIMIT
    limit.times { Authentication::EmailFloodThrottled.email_throttle("sign_in_link", member.email, tenant_key: "global").hit! }
    expect(Authentication::IssueSignInLink).not_to receive(:call)

    expect(described_class.call(user: member, customer_id: customer.id)).to be(false)
  end
end
