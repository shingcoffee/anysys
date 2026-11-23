# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::IssueCustomerSignup do
  it "enqueues mail for an unknown address without creating records" do
    before_customers = Customer.count
    before_users = Authentication::User.count

    expect {
      described_class.call(email: "  New@Acme.TEST ")
    }.to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(Customer.count).to eq(before_customers)
    expect(Authentication::User.count).to eq(before_users)
  end

  it "is a no-op when the address already belongs to a user" do
    create(:user, email: "taken@acme.test")
    before_customers = Customer.count
    before_users = Authentication::User.count

    expect {
      described_class.call(email: "  TAKEN@Acme.TEST ")
    }.not_to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)

    expect(ActionMailer::Base.deliveries).to be_empty
    expect(Customer.count).to eq(before_customers)
    expect(Authentication::User.count).to eq(before_users)
  end

  it "is a no-op for a blank email" do
    before_customers = Customer.count
    before_users = Authentication::User.count

    expect {
      described_class.call(email: "  ")
    }.not_to have_enqueued_mail(Authentication::CustomerSignupMailer, :instructions)

    expect(Customer.count).to eq(before_customers)
    expect(Authentication::User.count).to eq(before_users)
  end

  it "does not deliver inline" do
    described_class.call(email: "async@acme.test")

    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
