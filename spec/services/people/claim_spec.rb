# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Claim do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:entity) do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model)
  end
  let(:entry) { create(:entity_entry, entity: entity, customer: customer) }
  let(:user) { create(:user, :member, customer: customer) }
  let(:continuation) { { "action_key" => "enroll", "prefill" => { "course" => "12" } } }

  describe ".record!" do
    it "inserts a claim for the user and replaces a continuation-only claim on a second call" do
      freeze_time do
        claim = described_class.record!(user: user, continuation: continuation, created_user: false)

        expect(claim).to be_a(People::PendingClaim)
        expect(claim).to have_attributes(
          user_id: user.id,
          customer_id: customer.id,
          entity_entry_id: nil,
          created_user: false,
          continuation: continuation
        )
        expect(claim.expires_at).to eq(3.days.from_now)

        travel 1.hour
        later = { "action_key" => "donate", "prefill" => {} }
        updated = described_class.record!(user: user, continuation: later, created_user: false)

        expect(updated.id).to eq(claim.id)
        expect(updated.reload).to have_attributes(continuation: later, expires_at: 3.days.from_now)
        expect(People::PendingClaim.where(user_id: user.id).count).to eq(1)
      end
    end

    it "never replaces the claim recorded with the account it created" do
      claim = described_class.record!(user: user, entry: entry, continuation: continuation, created_user: true)

      kept = described_class.record!(user: user, continuation: { "action_key" => "donate", "prefill" => {} },
                                     created_user: false)

      expect(kept.id).to eq(claim.id)
      expect(claim.reload).to have_attributes(entity_entry_id: entry.id, created_user: true, continuation: continuation)
    end

    it "returns the stored claim when a concurrent insert wins the unique user index" do
      winner = described_class.record!(user: user, continuation: continuation, created_user: false)
      allow(People::PendingClaim).to receive(:find_or_initialize_by).and_return(People::PendingClaim.new(user_id: user.id))

      expect(described_class.record!(user: user, continuation: continuation, created_user: false)).to eq(winner)
    end
  end

  describe ".complete!" do
    it "links the entry, writes one person.claimed audit, and returns the continuation path" do
      described_class.record!(user: user, entry: entry, continuation: continuation, created_user: true)

      path = described_class.complete!(user)

      expect(path).to eq(Pages::ActionLink.path(customer_id: customer.id, action_key: "enroll", prefill: { "course" => "12" }))
      expect(entry.reload.user_id).to eq(user.id)
      expect(Authentication::Event.where(event: "person.claimed").count).to eq(1)
      expect(People::PendingClaim.find_by(user_id: user.id)).to be_nil
    end

    it "returns nil when there is nothing to complete" do
      expect(described_class.complete!(user)).to be_nil
    end
  end
end
