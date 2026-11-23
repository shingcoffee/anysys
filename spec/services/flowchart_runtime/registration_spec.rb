# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartRuntime::Registration do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:entity) do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model)
  end
  let(:plain_entity) { create(:entity, customer: customer, name: "Course") }
  let(:identity) { { "first_name" => "Pat", "last_name" => "Lee", "email" => "pat@example.com" } }
  let(:continuation) { { "action_key" => "enroll", "prefill" => { "course" => "12" } } }
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

  def enable_signup!(cust = customer, enabled: true)
    fm = enable_module!("authentication", cust)
    fm.set_extendable_model!(person_model, true)
    assignment = FeatureModules::CustomerAssignment.find_by!(
      customer_id: cust.id, feature_module_id: fm.id
    )
    assignment.update!(status: :active, configuration: { "allow_registration" => enabled }.to_json)
  end

  def disable_auth!(cust = customer)
    fm = FeatureModules::Module.find_by!(key: "authentication")
    assignment = FeatureModules::CustomerAssignment.find_by!(
      customer_id: cust.id, feature_module_id: fm.id
    )
    assignment.update!(status: :suspended)
  end

  def base_ctx(overrides = {})
    {
      audience: "public",
      bound_entity: entity,
      customer_id: customer.id,
      identity: identity,
      continuation: continuation,
      current_person_ids: {},
      errors: []
    }.merge(overrides)
  end

  def person_for(ctx)
    FlowchartRuntime::Entries.scope(ctx).new(customer_id: ctx[:customer_id])
  end

  def run(ctx = base_ctx, person: person_for(ctx))
    described_class.call(ctx, person: person)
  end

  before do
    allow(Billing::Quota::Guard).to receive(:check).and_return(allow_guard)
  end

  it "accepts an explicit identity hash" do
    enable_signup!
    ctx = base_ctx(identity: nil)
    result = described_class.call(ctx, person: person_for(ctx), identity: {
      "first_name" => "Pat", "last_name" => "Lee", "email" => "explicit@example.com"
    })
    expect(result).to eq("status" => "created")
  end

  it "fails public_only for member and admin runs" do
    enable_signup!
    %w[member admin].each do |audience|
      ctx = base_ctx(audience: audience)
      expect(run(ctx)).to be(false)
      expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.register_member.public_only")])
      expect(Authentication::User.find_by_normalized_email(identity["email"])).to be_nil
      expect(EntityEntry.where(entity: entity)).to be_empty
      expect(People::PendingClaim.count).to eq(0)
    end
  end

  it "fails person_entity_required unless the bound entity is a person entity" do
    enable_signup!
    ctx = base_ctx(bound_entity: plain_entity)
    expect(run(ctx)).to be(false)
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.register_member.person_entity_required")])
    expect(Authentication::User.find_by_normalized_email(identity["email"])).to be_nil
    expect(People::PendingClaim.count).to eq(0)
  end

  it "fails signup_disabled when the module is off or registration is not allowed" do
    enable_signup!(enabled: false)
    ctx = base_ctx
    expect(run(ctx)).to be(false)
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.register_member.signup_disabled")])

    ctx = base_ctx
    disable_auth!
    assignment = FeatureModules::CustomerAssignment.find_by!(
      customer_id: customer.id,
      feature_module_id: FeatureModules::Module.find_by!(key: "authentication").id
    )
    assignment.update!(configuration: { "allow_registration" => true }.to_json)
    expect(run(ctx)).to be(false)
    expect(ctx[:errors]).to eq([I18n.t("flowchart_runtime.errors.register_member.signup_disabled")])
    expect(Authentication::User.find_by_normalized_email(identity["email"])).to be_nil
    expect(People::PendingClaim.count).to eq(0)
  end

  it "registers a passwordless unconfirmed member, saves the person entry, and records a created claim" do
    enable_signup!
    ctx = base_ctx
    person = person_for(ctx)

    result = nil
    expect {
      result = run(ctx, person: person)
    }.to change(Authentication::User, :count).by(1)
      .and change(EntityEntry, :count).by(1)
      .and change(People::PendingClaim, :count).by(1)

    expect(result).to eq("status" => "created")
    user = Authentication::User.find_by_normalized_email("pat@example.com")
    expect(user).to have_attributes(
      first_name: "Pat", last_name: "Lee", customer_id: customer.id, confirmed_at: nil
    )
    expect(user.encrypted_password).to be_blank
    expect(user.member?).to eq(true)
    expect(user.password_set?).to eq(false)

    expect(person).to be_persisted
    expect(person.user_id).to be_nil
    expect(person.data_json).to include("first_name" => "Pat", "last_name" => "Lee", "email" => "pat@example.com")

    claim = People::PendingClaim.find_by!(user_id: user.id)
    expect(claim).to have_attributes(
      customer_id: customer.id,
      entity_entry_id: person.id,
      created_user: true,
      continuation: continuation
    )
    expect(ctx[:submission_outcome]).to eq("preset" => "registration_pending")
  end

  it "issues a sign-in link and a continuation-only claim for an existing active member of this tenant" do
    enable_signup!
    member = create(:user, :member, customer: customer, email: "member@example.com")
    expect(Authentication::IssueSignInLink).to receive(:call).with(email: member.email)

    ctx = base_ctx(identity: identity.merge("email" => "member@example.com"))
    users = Authentication::User.count
    entries = EntityEntry.count
    result = nil
    expect {
      result = run(ctx)
    }.to change(People::PendingClaim, :count).by(1)
    expect(Authentication::User.count).to eq(users)
    expect(EntityEntry.count).to eq(entries)

    expect(result).to eq("status" => "existing")
    claim = People::PendingClaim.find_by!(user_id: member.id)
    expect(claim).to have_attributes(
      entity_entry_id: nil,
      created_user: false,
      continuation: continuation
    )
    expect(ctx[:submission_outcome]).to eq("preset" => "registration_pending")
  end

  it "flags the record for discard when the email already belongs to a member" do
    enable_signup!
    create(:user, :member, customer: customer, email: "member@example.com")
    allow(Authentication::IssueSignInLink).to receive(:call)

    ctx = base_ctx(identity: identity.merge("email" => "member@example.com"))
    expect(run(ctx)).to eq("status" => "existing")
    expect(ctx[:discard_record]).to be(true)
  end

  it "saves nothing and sends no email for an existing admin, owner, or another tenant's user" do
    enable_signup!
    enable_module!("authentication", other_customer).set_extendable_model!(person_model, true)
    admin = create(:user, :admin, customer: customer, email: "admin@example.com")
    foreign = create(:user, :member, customer: other_customer, email: "foreign@example.com")
    expect(Authentication::IssueSignInLink).not_to receive(:call)

    [admin, foreign].each do |user|
      ctx = base_ctx(identity: identity.merge("email" => user.email))
      users = Authentication::User.count
      entries = EntityEntry.count
      claims = People::PendingClaim.count
      result = run(ctx)
      expect(Authentication::User.count).to eq(users)
      expect(EntityEntry.count).to eq(entries)
      expect(People::PendingClaim.count).to eq(claims)

      expect(result).to eq("status" => "existing")
      expect(People::PendingClaim.find_by(user_id: user.id)).to be_nil
      expect(ctx[:submission_outcome]).to eq("preset" => "registration_pending")
    end
  end

  it "answers a full member quota like a taken address and saves nothing" do
    enable_signup!
    allow(Billing::Quota::Guard).to receive(:check).and_return(deny_guard)
    ctx = base_ctx(identity: identity.merge("email" => "full@example.com"))

    users = Authentication::User.count
    entries = EntityEntry.count
    claims = People::PendingClaim.count
    result = run(ctx)
    expect(Authentication::User.count).to eq(users)
    expect(EntityEntry.count).to eq(entries)
    expect(People::PendingClaim.count).to eq(claims)

    expect(result).to eq("status" => "existing")
    expect(ctx[:errors]).to be_empty
    expect(ctx[:submission_outcome]).to eq("preset" => "registration_pending")
  end

  it "leaves an unconfirmed member's pending claim alone on a repeat submission" do
    enable_signup!
    first = base_ctx
    expect(run(first)).to eq("status" => "created")
    user = Authentication::User.find_by_normalized_email(identity["email"])
    claim = People::PendingClaim.find_by!(user_id: user.id)
    expect(Authentication::IssueSignInLink).not_to receive(:call)

    repeat = base_ctx(continuation: { "action_key" => "donate", "prefill" => {} })
    expect(run(repeat)).to eq("status" => "existing")

    expect(claim.reload).to have_attributes(
      entity_entry_id: claim.entity_entry_id, created_user: true, continuation: continuation
    )
    expect(claim.entity_entry_id).to be_present
    expect(repeat[:submission_outcome]).to eq("preset" => "registration_pending")
  end

  it "stops mailing an existing member once the sign-in link flood limit is reached but keeps the claim" do
    enable_signup!
    Authentication::Throttle.reset_store!
    member = create(:user, :member, customer: customer, email: "member@example.com")
    limit = Authentication::EmailFloodThrottled::DEFAULT_LIMIT
    expect(Authentication::IssueSignInLink).to receive(:call).with(email: member.email).exactly(limit).times

    (limit + 2).times do
      ctx = base_ctx(identity: identity.merge("email" => member.email))
      expect(run(ctx)).to eq("status" => "existing")
      expect(ctx[:submission_outcome]).to eq("preset" => "registration_pending")
    end

    throttled = base_ctx(
      identity: identity.merge("email" => member.email),
      continuation: { "action_key" => "donate", "prefill" => {} }
    )
    run(throttled)
    expect(People::PendingClaim.find_by!(user_id: member.id)).to have_attributes(
      created_user: false, entity_entry_id: nil, continuation: { "action_key" => "donate", "prefill" => {} }
    )
  ensure
    Authentication::Throttle.reset_store!
  end

  it "sets the registration_pending outcome preset only when the flowchart has not set one" do
    enable_signup!
    existing = { "preset" => "thank_you", "flash" => "notice" }
    ctx = base_ctx(submission_outcome: existing, identity: identity.merge("email" => "kept@example.com"))
    expect(run(ctx)).to eq("status" => "created")
    expect(ctx[:submission_outcome]).to eq(existing)

    ctx = base_ctx(identity: identity.merge("email" => "fresh@example.com"))
    expect(run(ctx)).to eq("status" => "created")
    expect(ctx[:submission_outcome]).to eq("preset" => "registration_pending")
  end

  it "rejects blank or invalid identity before the email lookup, the same way save_model reports record_invalid" do
    enable_signup!
    taken = create(:user, :member, customer: customer, email: "taken@example.com")
    expect(Authentication::IssueSignInLink).not_to receive(:call)

    ctx = base_ctx(identity: { "first_name" => "", "last_name" => "", "email" => "" })
    users = Authentication::User.count
    claims = People::PendingClaim.count
    expect(run(ctx)).to be(false)
    expect(Authentication::User.count).to eq(users)
    expect(People::PendingClaim.count).to eq(claims)
    expect(ctx[:error_details].last).to include("code" => "record_invalid")
    expect(ctx[:errors]).to be_present

    ctx = base_ctx(identity: { "first_name" => "", "last_name" => "Lee", "email" => taken.email })
    expect(run(ctx)).to be(false)
    expect(People::PendingClaim.find_by(user_id: taken.id)).to be_nil
  end
end
