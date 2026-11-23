# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Mfa::Operation::RequestResetLink do
  let_it_be(:customer) { create(:customer) }
  let(:member)   { create(:user, :member, :with_mfa, customer: customer, email: "alice@example.com") }
  let(:admin)    { create(:user, :admin, :with_mfa, customer: customer, email: "bob@example.com") }

  before { ActionMailer::Base.deliveries.clear }

  # Runs the operation with jobs performed inline (so any reset mail is delivered
  # synchronously) and returns the operation result.
  def request_reset(email)
    perform_enqueued_jobs { described_class.call(customer_id: customer.id, email: email) }
  end

  it "delivers a reset email when the email matches a member" do
    member  # ensure factory has run
    expect { expect(request_reset(member.email)).to be_success }
      .to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(ActionMailer::Base.deliveries.last.to).to eq([member.email])
  end

  it "is silent (no email) when the address belongs to an admin" do
    admin
    expect { expect(request_reset(admin.email)).to be_success }
      .not_to change { ActionMailer::Base.deliveries.size }
  end

  it "is silent (no email) when the address is unknown" do
    expect { expect(request_reset("ghost@example.com")).to be_success }
      .not_to change { ActionMailer::Base.deliveries.size }
  end

  it "matches email case-insensitively and trims whitespace" do
    member
    expect { request_reset("  ALICE@EXAMPLE.COM ") }
      .to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  it "is silent when a blank email is passed" do
    expect { expect(request_reset("")).to be_success }
      .not_to change { ActionMailer::Base.deliveries.size }
  end

  it "is silent when a member without MFA configured requests a reset" do
    member_no_mfa = create(:user, :member, customer: customer, email: "nomfa@example.com")
    expect { expect(request_reset(member_no_mfa.email)).to be_success }
      .not_to change { ActionMailer::Base.deliveries.size }
  end
end
