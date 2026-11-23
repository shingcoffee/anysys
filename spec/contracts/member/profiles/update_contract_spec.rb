# frozen_string_literal: true

require "rails_helper"

RSpec.describe Member::Profiles::UpdateContract do
  let(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer) }

  def contract_for(record = user)
    described_class.new(record)
  end

  it "validates first_name presence and length" do
    contract = contract_for
    expect(contract.validate(first_name: "", last_name: user.last_name, email: user.email)).to be false
    expect(contract.errors[:first_name]).to include(/blank/i)

    contract = contract_for
    expect(contract.validate(first_name: "x" * 51, last_name: user.last_name, email: user.email)).to be false
    expect(contract.errors[:first_name]).to include(/too long/i)
  end

  it "validates email format and uniqueness scoped to the customer" do
    create(:user, :member, customer: customer, email: "taken@example.com")
    contract = contract_for
    expect(contract.validate(first_name: "Lin", last_name: "Vega", email: "taken@example.com")).to be false
    expect(contract.errors[:email]).to be_present
  end

  it "accepts a valid payload and saves" do
    contract = contract_for
    expect(contract.validate(
      first_name: "Lin", last_name: "Vega", email: "lin@example.com",
      current_password: "password123"
    )).to be true
    contract.save
    expect(user.reload.email).to eq("lin@example.com")
  end

  it "lets a member change name without current_password when email is unchanged" do
    contract = contract_for
    expect(contract.validate(
      first_name: "Lin", last_name: user.last_name, email: user.email
    )).to be true
  end

  it "rejects an email change when current_password is missing" do
    contract = contract_for
    expect(contract.validate(
      first_name: user.first_name, last_name: user.last_name,
      email: "new@example.com"
    )).to be false
    expect(contract.errors[:current_password]).to be_present
  end

  it "rejects an email change when current_password is wrong" do
    contract = contract_for
    expect(contract.validate(
      first_name: user.first_name, last_name: user.last_name,
      email: "new@example.com", current_password: "wrong-password"
    )).to be false
    expect(contract.errors[:current_password]).to be_present
  end

  it "rejects an email change for a passwordless account" do
    user.update_columns(encrypted_password: "")
    contract = contract_for
    expect(contract.validate(
      first_name: user.first_name, last_name: user.last_name,
      email: "hijacked@example.com"
    )).to be false
    expect(contract.errors[:email]).to be_present
    expect(user.reload.email).not_to eq("hijacked@example.com")
  end

  it "validates last_name presence and length" do
    contract = contract_for
    expect(contract.validate(first_name: "Lin", last_name: "", email: user.email)).to be false
    expect(contract.errors[:last_name]).to include(/blank/i)

    contract = contract_for
    expect(contract.validate(first_name: "Lin", last_name: "x" * 51, email: user.email)).to be false
    expect(contract.errors[:last_name]).to include(/too long/i)
  end

  it "skips the uniqueness check when email is blank (presence catches it instead)" do
    contract = contract_for
    result = contract.validate(first_name: "Lin", last_name: "Vega", email: "")
    expect(result).to be false
    # email presence error, but no uniqueness error — blank guard fires
    expect(contract.errors[:email]).to include(/blank/i)
  end

  it "allows a user to re-save their own email (not flagged as duplicate)" do
    contract = contract_for
    expect(contract.validate(first_name: user.first_name, last_name: user.last_name, email: user.email)).to be true
  end

  it "rejects a duplicate email for a new (unpersisted) user record" do
    existing_email = create(:user, :member, customer: customer).email
    new_user = Authentication::User.new(customer: customer)
    contract = contract_for(new_user)
    result = contract.validate(first_name: "Lin", last_name: "Vega", email: existing_email)
    expect(result).to be false
    expect(contract.errors[:email]).to be_present
  end
end
