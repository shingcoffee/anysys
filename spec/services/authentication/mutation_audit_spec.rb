# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::MutationAudit do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :member, :mfa_configured, customer: customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let(:request) { instance_double(ActionDispatch::Request, remote_ip: "203.0.113.5", user_agent: "AuditSpec") }

  before { Authentication::Throttle.reset_store! }
  after { Authentication::Throttle.reset_store! }

  def enable_mfa
    described_class.mfa(user: user, actor: user, request: request, source: "self_service") { user.enable_mfa! }
  end

  it "records MFA outcome facts through the existing ledger without recording credentials" do
    secret = user.otp_secret
    digest = user.encrypted_password

    expect { enable_mfa }
      .to change { Authentication::Event.where(event: "mfa_enabled", user_id: user.id).count }.by(1)

    event = Authentication::Event.where(event: "mfa_enabled", user_id: user.id).last
    expect(event.customer_id).to eq(customer.id)
    expect(event.ip).to eq("203.0.113.5")
    expect(event.metadata).to eq(
      "actor_id" => user.id, "source" => "self_service", "outcome" => "success",
      "before" => { "required" => false, "configured" => true },
      "after" => { "required" => true, "configured" => true }
    )
    expect(event.metadata.to_json).not_to include(secret, digest)
  end

  it "does not record a failed verification or an unchanged MFA state" do
    expect {
      result = described_class.mfa(user: user, actor: user, source: "self_service") do
        Member::Mfa::Operation::Enable.call(user: user, code: "invalid-code")
      end
      expect(result.success?).to be(false)
    }.not_to change { Authentication::Event.where(event: "mfa_enabled", user_id: user.id).count }

    expect(user.reload.mfa_required?).to be(false)
    enable_mfa
    expect { enable_mfa }
      .not_to change { Authentication::Event.where(event: "mfa_enabled", user_id: user.id).count }
  end

  it "rolls back the MFA outcome row with the mutation and emits no committed-success log" do
    user
    expect(Rails.logger).not_to receive(:info).with(a_string_matching(/\[auth\] mfa_enabled/))

    expect {
      Authentication::User.transaction(requires_new: true) do
        enable_mfa
        expect(user.reload.mfa_required?).to be(true)
        raise ActiveRecord::Rollback
      end
    }.not_to change { Authentication::Event.where(event: "mfa_enabled", user_id: user.id).count }

    expect(user.reload.mfa_required?).to be(false)
  end

  it "records both sides of an in-place reserved-role replacement and its actor" do
    member_role = user.customer.roles.find_by!(key: "member")
    admin_role = user.customer.roles.find_by!(key: "admin")
    actor
    first_id = Authentication::Event.maximum(:id) || 0

    result = UserRoles::Operation::Assign.call(user: user, role_ids: [admin_role.id], actor: actor, request: request)

    expect(result.success?).to be(true)
    events = Authentication::Event.where(user_id: user.id).where("id > ?", first_id).order(:id)
    expect(events.pluck(:event)).to eq(%w[role_revoked role_granted])
    expect(events.map { |event| event.metadata["role_ids"] }).to eq([[member_role.id], [admin_role.id]])
    events.each do |event|
      expect(event.metadata).to include(
        "actor_id" => actor.id, "source" => "role_assignment", "outcome" => "success",
        "before" => { "role_ids" => [member_role.id] }, "after" => { "role_ids" => [admin_role.id] }
      )
      expect(event.metadata.to_json).not_to include(user.otp_secret, user.encrypted_password)
    end
  end

  it "does not audit a no-op role assignment" do
    member_role = user.customer.roles.find_by!(key: "member")

    expect {
      result = UserRoles::Operation::Assign.call(user: user, role_ids: [member_role.id], actor: actor)
      expect(result.success?).to be(true)
    }.not_to change { Authentication::Event.where(user_id: user.id, event: %w[role_granted role_revoked]).count }
  end

  it "rolls role events back with an enclosing profile/assignment transaction" do
    user
    actor
    admin_role = customer.roles.find_by!(key: "admin")
    original_name = user.first_name

    expect {
      Authentication::User.transaction(requires_new: true) do
        user.update!(first_name: "RolledBack")
        result = UserRoles::Operation::Assign.call(user: user, role_ids: [admin_role.id], actor: actor)
        expect(result.success?).to be(true)
        raise ActiveRecord::Rollback
      end
    }.not_to change { Authentication::Event.where(user_id: user.id, event: %w[role_granted role_revoked]).count }

    expect(user.reload.first_name).to eq(original_name)
    expect(user.member?).to be(true)
    expect(user.admin?).to be(false)
  end
end
