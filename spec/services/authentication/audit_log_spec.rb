# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::AuditLog do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user)     { create(:user, customer: customer) }

  # Capture the notification payload synchronously without relying on the
  # process-wide Authentication::Instrumentation subscriber (already attached
  # at boot), so this spec only asserts what AuditLog itself emits.
  def captured_payload
    payload = nil
    callback = ->(*args) { payload = ActiveSupport::Notifications::Event.new(*args).payload }
    ActiveSupport::Notifications.subscribed(callback, "authentication.event") { yield }
    payload
  end

  describe ".record" do
    it "emits an authentication.event notification with the given event name" do
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user) }
      expect(payload[:event]).to eq("login_succeeded")
    end

    it "stringifies a symbol event name" do
      payload = captured_payload { described_class.record(event: :mfa_failed, user: user) }
      expect(payload[:event]).to be_a(String)
    end

    it "includes the user id" do
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user) }
      expect(payload[:user_id]).to eq(user.id)
    end

    it "is nil for user_id when no user is given" do
      payload = captured_payload { described_class.record(event: :login_failed, customer_id: customer.id) }
      expect(payload[:user_id]).to be_nil
    end

    it "prefers the explicit customer_id over the user's customer_id" do
      other_customer = create(:customer)
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user, customer_id: other_customer.id) }
      expect(payload[:customer_id]).to eq(other_customer.id)
    end

    it "falls back to the user's customer_id when none is given explicitly" do
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user) }
      expect(payload[:customer_id]).to eq(user.customer_id)
    end

    it "is nil for customer_id when neither customer_id nor a user is given" do
      payload = captured_payload { described_class.record(event: :login_failed) }
      expect(payload[:customer_id]).to be_nil
    end

    it "captures the request's remote_ip and user_agent when a request is given" do
      request = instance_double(ActionDispatch::Request, remote_ip: "203.0.113.5", user_agent: "TestAgent/1.0")
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user, request: request) }
      expect(payload[:ip]).to eq("203.0.113.5")
      expect(payload[:user_agent]).to eq("TestAgent/1.0")
    end

    it "is nil for ip/user_agent when no request is given" do
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user) }
      expect(payload[:ip]).to be_nil
      expect(payload[:user_agent]).to be_nil
    end

    it "truncates an oversized user_agent to 500 characters" do
      request = instance_double(ActionDispatch::Request, remote_ip: "203.0.113.5", user_agent: "A" * 900)
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user, request: request) }
      expect(payload[:user_agent].length).to eq(500)
    end

    it "forwards arbitrary keyword args as metadata" do
      payload = captured_payload { described_class.record(event: :role_granted, user: user, actor_id: 42, role_ids: [1, 2]) }
      expect(payload[:metadata]).to eq(actor_id: 42, role_ids: [1, 2])
    end

    it "defaults metadata to an empty hash" do
      payload = captured_payload { described_class.record(event: :login_succeeded, user: user) }
      expect(payload[:metadata]).to eq({})
    end
  end

  describe "end-to-end persistence via the live process subscriber" do
    # Authentication::Instrumentation.subscribe! is attached once at boot
    # (config/initializers/authentication_instrumentation.rb); this proves
    # AuditLog.record actually reaches the ledger through that real pipeline
    # rather than only asserting the notification payload shape.
    it "creates an Authentication::Event row" do
      expect {
        described_class.record(event: :login_succeeded, user: user, customer_id: customer.id)
      }.to change { Authentication::Event.where(event: "login_succeeded", user_id: user.id).count }.by(1)
    end
  end
end
