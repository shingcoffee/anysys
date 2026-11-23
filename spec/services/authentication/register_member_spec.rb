# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::RegisterMember do
  # Devise mail is enqueued; deliver it so examples can read the mailbox.
  around { |example| perform_enqueued_jobs { example.run } }

  let_it_be(:customer) { create(:customer) }

  let(:allow_guard) do
    instance_double(Billing::Quota::Guard::Result, allowed?: true, message: "allowed")
  end
  let(:deny_guard) do
    instance_double(
      Billing::Quota::Guard::Result,
      allowed?: false,
      message: I18n.t("comp_billing.quota.limit_reached", limit: 1, label: "Members")
    )
  end

  let(:valid_attributes) do
    {
      first_name: "Pat",
      last_name: "Lee",
      email: "pat@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    }
  end

  before do
    allow(Billing::Quota::Guard).to receive(:check).and_return(allow_guard)
  end

  def register(customer: self.customer, passwordless: false, request: nil, **overrides)
    attributes = valid_attributes.merge(overrides)
    attributes = attributes.except(:password, :password_confirmation) if passwordless

    described_class.call(
      customer: customer,
      attributes: attributes,
      request: request,
      passwordless: passwordless
    )
  end

  it "creates an unconfirmed member with the member role" do
    result = register

    expect(result.status).to eq(:created)
    user = result.user
    expect(user).to be_persisted
    expect(user.confirmed_at).to be_nil
    expect(user.confirmation_token).to be_present
    expect(user.member?).to eq(true)
    expect(user.admin?).to eq(false)
    expect(user.owner?).to eq(false)
    expect(user.reserved_role_keys).to eq(["member"])
    expect(user.customer_id).to eq(customer.id)
  end

  it "creates a passwordless user with no encrypted_password" do
    result = register(passwordless: true, email: "link@example.com")

    expect(result.status).to eq(:created)
    expect(result.user.encrypted_password).to be_blank
    expect(result.user.password_set?).to eq(false)
    expect(result.user.member?).to eq(true)
    expect(result.user.confirmed_at).to be_nil
  end

  it "returns :quota_exceeded and creates no user when the member quota is exhausted" do
    allow(Billing::Quota::Guard).to receive(:check).and_return(deny_guard)

    result = nil
    expect {
      result = register(email: "full@example.com")
    }.not_to change(Authentication::User, :count)

    expect(result.status).to eq(:quota_exceeded)
    expect(result.user).not_to be_persisted
    expect(result.errors).to be_present
    expect(Authentication::User.exists?(email: "full@example.com")).to eq(false)
  end

  it "returns :invalid with errors and no role row when attributes are invalid" do
    result = nil
    expect {
      result = register(
        first_name: "",
        last_name: "",
        email: "not-an-email",
        password: "short",
        password_confirmation: "mismatch"
      )
    }.not_to change(UsersRole, :count)

    expect(result.status).to eq(:invalid)
    expect(result.user).not_to be_persisted
    expect(result.errors).to be_present
    expect(result.errors[:email]).to be_present
    expect(Authentication::User.exists?(email: "not-an-email")).to eq(false)
  end

  it "treats losing the unique email index race as a taken address" do
    allow_any_instance_of(Authentication::User).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

    result = register

    expect(result.status).to eq(:invalid)
    expect(result.errors.of_kind?(:email, :taken)).to be(true)
  end

  it "sends the confirmation email once after the lock transaction commits" do
    deliveries_inside_lock = nil
    allow(customer).to receive(:with_lock).and_wrap_original do |method, *args, **kwargs, &block|
      method.call(*args, **kwargs) do
        value = block.call
        deliveries_inside_lock = ActionMailer::Base.deliveries.size
        value
      end
    end

    expect(Authentication::User).not_to receive(:send_confirmation_instructions)

    expect { register }.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(deliveries_inside_lock).to eq(ActionMailer::Base.deliveries.size - 1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(["pat@example.com"])
  end

  it "checks the quota guard inside customer.with_lock and creates nothing on a later deny" do
    inside_lock = false
    checked_inside_lock = []

    allow(customer).to receive(:with_lock).and_wrap_original do |method, *args, **kwargs, &block|
      method.call(*args, **kwargs) do
        inside_lock = true
        begin
          block.call
        ensure
          inside_lock = false
        end
      end
    end

    allow(Billing::Quota::Guard).to receive(:check) do |**kwargs|
      expect(kwargs[:customer]).to eq(customer)
      expect(kwargs[:item_key]).to eq("member")
      checked_inside_lock << inside_lock
      checked_inside_lock.size == 1 ? allow_guard : deny_guard
    end

    first = register(email: "first@example.com")
    expect(first.status).to eq(:created)
    expect(Authentication::User.exists?(email: "first@example.com")).to eq(true)

    second = nil
    expect {
      second = register(email: "second@example.com")
    }.not_to change { Authentication::User.exists?(email: "second@example.com") }

    expect(second.status).to eq(:quota_exceeded)
    expect(checked_inside_lock).to eq([true, true])
  end

  it "creates the user under the given customer only" do
    other = create(:customer)

    result = described_class.call(
      customer: customer,
      attributes: valid_attributes.merge(email: "isolated@example.com", customer_id: other.id)
    )

    expect(result.status).to eq(:created)
    expect(result.user.customer_id).to eq(customer.id)
    expect(Authentication::User.exists?(email: "isolated@example.com", customer_id: other.id)).to eq(false)
    expect(Authentication::User.where(customer_id: other.id, email: "isolated@example.com")).to be_empty
  end
end
