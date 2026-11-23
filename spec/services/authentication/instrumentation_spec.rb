# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::Instrumentation do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:user)     { create(:user, customer: customer) }
  let(:instrumentation) { described_class.new }

  def build_event(payload)
    ActiveSupport::Notifications::Event.new("authentication.event", Time.current, Time.current, "id", payload)
  end

  describe "WARN_EVENTS" do
    it "flags the security-significant failure events for warn-level logging" do
      expect(described_class::WARN_EVENTS).to match_array(%w[login_failed locked_out mfa_failed throttled])
    end
  end

  describe "#persist" do
    it "creates an Authentication::Event row from the notification payload" do
      payload = { event: "login_succeeded", user_id: user.id, customer_id: customer.id,
                  ip: "203.0.113.9", user_agent: "TestUA", metadata: { foo: "bar" } }

      expect { instrumentation.persist(payload) }
        .to change { Authentication::Event.count }.by(1)

      row = Authentication::Event.last
      expect(row.event).to eq("login_succeeded")
      expect(row.user_id).to eq(user.id)
      expect(row.customer_id).to eq(customer.id)
      expect(row.ip).to eq("203.0.113.9")
      expect(row.user_agent).to eq("TestUA")
      expect(row.metadata).to eq("foo" => "bar")
    end

    it "defaults metadata to an empty hash when absent" do
      instrumentation.persist(event: "logout", user_id: user.id, customer_id: customer.id)
      expect(Authentication::Event.last.metadata).to eq({})
    end

    it "persists a nil user_id for pre-auth events (e.g. a failed login for an unknown email)" do
      instrumentation.persist(event: "login_failed", user_id: nil, customer_id: customer.id)
      expect(Authentication::Event.last.user_id).to be_nil
    end

    it "swallows a persist failure rather than raising (logging must never break auth)" do
      allow(Authentication::Event).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Authentication::Event.new))

      expect {
        instrumentation.persist(event: "login_succeeded", user_id: user.id, customer_id: customer.id)
      }.not_to raise_error
    end

    it "logs a warning when persistence fails" do
      allow(Authentication::Event).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Authentication::Event.new))
      expect(Rails.logger).to receive(:warn).with(/persist failed for login_succeeded/)

      instrumentation.persist(event: "login_succeeded", user_id: user.id, customer_id: customer.id)
    end
  end

  describe "#log" do
    it "logs at warn level for WARN_EVENTS" do
      expect(Rails.logger).to receive(:warn).with(a_string_matching(/\[auth\] login_failed/))
      instrumentation.log(event: "login_failed", user_id: user.id, customer_id: customer.id, ip: "1.2.3.4")
    end

    it "logs at info level for events not in WARN_EVENTS" do
      expect(Rails.logger).to receive(:info).with(a_string_matching(/\[auth\] login_succeeded/))
      instrumentation.log(event: "login_succeeded", user_id: user.id, customer_id: customer.id, ip: "1.2.3.4")
    end

    it "renders '-' placeholders when user_id/customer_id/ip are absent" do
      expect(Rails.logger).to receive(:info).with("[auth] logout user=- customer=- ip=-")
      instrumentation.log(event: "logout", user_id: nil, customer_id: nil, ip: nil)
    end

    it "swallows a logger IO error rather than propagating it (logging must never break auth)" do
      # ActiveSupport::Notifications reraises subscriber exceptions synchronously,
      # so a raising logger here would otherwise bubble up into the auth flow.
      allow(Rails.logger).to receive(:info).and_raise(IOError, "log device full")
      allow(Rails.logger).to receive(:warn).and_raise(IOError, "log device full")

      expect {
        instrumentation.log(event: "login_succeeded", user_id: user.id, customer_id: customer.id, ip: "1.2.3.4")
      }.not_to raise_error
    end
  end

  describe "#handle" do
    it "persists and logs the event from a Notifications::Event" do
      payload = { event: "mfa_verified", user_id: user.id, customer_id: customer.id, ip: "9.9.9.9" }
      event = build_event(payload)

      expect(Rails.logger).to receive(:info).with(a_string_matching(/\[auth\] mfa_verified/))
      expect { instrumentation.handle(event) }.to change { Authentication::Event.count }.by(1)
    end

    it "does not propagate a logger IO error out of the notification subscriber" do
      event = build_event(event: "mfa_verified", user_id: user.id, customer_id: customer.id, ip: "9.9.9.9")
      allow(Rails.logger).to receive(:info).and_raise(IOError, "log device full")
      allow(Rails.logger).to receive(:warn).and_raise(IOError, "log device full")

      expect { instrumentation.handle(event) }.not_to raise_error
    end

    it "persists mutation facts but waits for the commit boundary before logging success" do
      commit_callbacks = []
      allow(ActiveRecord).to receive(:after_all_transactions_commit) { |&block| commit_callbacks << block }
      event = build_event(event: "mfa_enabled", user_id: user.id, customer_id: customer.id, defer_logging: true)
      allow(Rails.logger).to receive(:info)

      expect { instrumentation.handle(event) }.to change { Authentication::Event.count }.by(1)
      expect(Rails.logger).not_to have_received(:info).with(a_string_matching(/\[auth\] mfa_enabled/))

      commit_callbacks.each(&:call)
      expect(Rails.logger).to have_received(:info).with(a_string_matching(/\[auth\] mfa_enabled/)).once
    end
  end

  describe ".subscribe!" do
    # The live "authentication.event" channel already has the boot-time
    # subscriber attached (config/initializers/authentication_instrumentation.rb).
    # Subscribing a second real listener here would double-persist every
    # event fired for the rest of the suite, so this stubs
    # ActiveSupport::Notifications.subscribe to capture the block .subscribe!
    # registers and drives it directly, without touching the live channel.
    it "registers a block on the authentication.event channel that delegates to a new instance's #handle" do
      captured_block = nil
      allow(ActiveSupport::Notifications).to receive(:subscribe) do |name, &block|
        captured_block = block if name == "authentication.event"
      end

      described_class.subscribe!

      expect(captured_block).to be_a(Proc)

      instance = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(instance)
      expect(instance).to receive(:handle).with(instance_of(ActiveSupport::Notifications::Event))

      captured_block.call("authentication.event", Time.current, Time.current, "id", { event: "login_succeeded" })
    end
  end
end
