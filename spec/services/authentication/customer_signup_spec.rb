# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::CustomerSignup do
  def call(email: "founder@acme.test")
    described_class.call(email: email)
  end

  it "creates an active customer and a confirmed admin" do
    result = call

    expect(result.success?).to be(true)
    expect(result.customer).to be_active
    expect(result.customer.id).not_to eq(Authentication::User::PLATFORM_CUSTOMER_ID)
    expect(result.user).to be_confirmed
    expect(result.user.admin?).to be(true)
    expect(result.user.owner?).to be(false)
    expect(result.user.member?).to be(false)
    expect(result.user.password_set?).to be(false)
    expect(Authentication::User.where(customer: result.customer).count).to eq(1)
    expect(result.user.reserved_role_keys).to eq(["admin"])
  end

  it "does not send a Devise confirmation email" do
    expect { call }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "rejects a taken email and leaves no orphan customer" do
    existing = create(:user, email: "taken@acme.test")
    before = Customer.count

    result = call(email: existing.email)

    expect(result.success?).to be(false)
    expect(Customer.count).to eq(before)
  end

  it "does not create a tenant when public sign-up is disabled" do
    Authentication::PlatformSettings.instance.update!(allow_customer_signup: false)

    expect { call }.not_to change(Customer, :count)
    expect(call.success?).to be(false)
  end

  it "rolls both tenant and user back when the initial reserved assignment fails" do
    allow_any_instance_of(UsersRole).to receive(:save!).and_wrap_original do |method, *args, **kwargs|
      record = method.receiver
      if record.user&.email == "founder@acme.test"
        record.errors.add(:base, I18n.t("auth.errors.reserved_role_required"))
        raise ActiveRecord::RecordInvalid.new(record)
      end
      method.call(*args, **kwargs)
    end
    before_customers = Customer.count
    before_users = Authentication::User.count

    result = call

    expect(result.success?).to be(false)
    expect(Customer.count).to eq(before_customers)
    expect(Authentication::User.count).to eq(before_users)
  end

  # Two concurrent confirms of the same link: neither request sees the other's
  # uncommitted row, so both pass the uniqueness *validation* and the loser
  # hits the unique index on LOWER(email) instead. Uncaught, that reached the
  # controller as a 500 on a flow the user had in fact completed.
  context "when a concurrent request wins the race on the same email" do
    before do
      allow_any_instance_of(Authentication::User)
        .to receive(:save)
        .and_raise(ActiveRecord::RecordNotUnique, "duplicate key value violates unique index")
    end

    it "reports a plain failure rather than raising" do
      result = nil
      expect { result = call }.not_to raise_error
      expect(result.success?).to be(false)
      expect(result.errors).to be_present
    end

    it "leaves no orphan tenant behind" do
      expect { call }.not_to change(Customer, :count)
    end
  end
end
