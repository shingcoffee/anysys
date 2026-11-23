# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::Event, type: :model do
  let_it_be(:customer_a) { create(:customer) }
  let_it_be(:customer_b) { create(:customer) }
  let_it_be(:user_a)     { create(:user, customer: customer_a) }
  let_it_be(:user_b)     { create(:user, customer: customer_b) }

  describe "EVENTS" do
    it "lists the full set of auth event kinds" do
      expect(described_class::EVENTS).to match_array(%w[
        login_succeeded login_failed logout locked_out
        mfa_enabled mfa_disabled mfa_verified mfa_failed
        password_reset_requested password_reset_completed
        role_granted role_revoked throttled
        oauth_authorized
      ])
    end
  end

  describe "validations" do
    it "requires an event" do
      event = described_class.new(event: nil)
      expect(event).not_to be_valid
      expect(event.errors[:event]).to be_present
    end

    it "is valid with a bare event and no customer/user (pre-auth failures)" do
      event = described_class.new(event: "login_failed")
      expect(event).to be_valid
    end
  end

  describe "table_name" do
    it "backs onto authentication_events" do
      expect(described_class.table_name).to eq("authentication_events")
    end
  end

  describe "tenant isolation — NOT TenantScoped" do
    # This ledger is intentionally global: pre-auth failures may not resolve
    # a tenant, and cross-tenant audit review (platform owner) needs to see
    # every row. Unlike TenantScoped models, a bare `.all`/`.create!` here is
    # NOT implicitly filtered by Current.customer — scoping is the caller's
    # job via for_customer/for_user.
    it "does not automatically scope records to Current.customer" do
      described_class.create!(event: "login_succeeded", customer_id: customer_a.id, user_id: user_a.id)
      described_class.create!(event: "login_succeeded", customer_id: customer_b.id, user_id: user_b.id)

      Current.customer = customer_a

      expect(described_class.all.map(&:customer_id)).to include(customer_a.id, customer_b.id)
    ensure
      Current.customer = nil
    end
  end

  describe "scopes" do
    let!(:event_a1) { described_class.create!(event: "login_succeeded", customer_id: customer_a.id, user_id: user_a.id) }
    let!(:event_a2) { described_class.create!(event: "login_failed", customer_id: customer_a.id, user_id: nil) }
    let!(:event_b1) { described_class.create!(event: "login_succeeded", customer_id: customer_b.id, user_id: user_b.id) }

    describe ".for_customer" do
      it "returns only rows for the given customer" do
        expect(described_class.for_customer(customer_a.id)).to contain_exactly(event_a1, event_a2)
      end

      it "does not leak another tenant's rows" do
        expect(described_class.for_customer(customer_a.id)).not_to include(event_b1)
      end
    end

    describe ".for_user" do
      it "returns only rows for the given user" do
        expect(described_class.for_user(user_a.id)).to contain_exactly(event_a1)
      end
    end

    describe ".recent" do
      it "returns rows created at or after the given time" do
        old_event = described_class.create!(event: "logout", customer_id: customer_a.id, user_id: user_a.id,
                                            created_at: 2.days.ago)
        expect(described_class.recent(1.day.ago)).not_to include(old_event)
        expect(described_class.recent(1.day.ago)).to include(event_a1)
      end
    end
  end

  describe "metadata" do
    it "defaults to an empty hash" do
      event = described_class.create!(event: "mfa_verified", customer_id: customer_a.id, user_id: user_a.id)
      expect(event.reload.metadata).to eq({})
    end

    it "persists arbitrary JSON metadata" do
      event = described_class.create!(event: "throttled", customer_id: customer_a.id,
                                      metadata: { "flow" => "mfa" })
      expect(event.reload.metadata).to eq("flow" => "mfa")
    end
  end
end
