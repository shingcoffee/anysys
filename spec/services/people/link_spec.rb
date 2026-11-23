# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Link do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:entity) do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    create(:entity, customer: customer, name: "Student", extended_model: person_model)
  end
  let(:entry) { create(:entity_entry, entity: entity, customer: customer) }

  describe ".link!" do
    it "returns a Result from the link activity" do
      actor = create(:user, :admin, customer: customer)
      user = create(:user, customer: customer)

      linked = described_class.link!(entry: entry, user_id: user.id, actor: actor)
      expect(linked).to be_a(described_class::Result)
      expect(linked).to be_success
      expect(linked.entry.reload.user_id).to eq(user.id)
    end

    it "writes person.linked by default and accepts an event: override" do
      actor = create(:user, :admin, customer: customer)
      user = create(:user, customer: customer)

      described_class.link!(entry: entry, user_id: user.id, actor: actor)
      expect(Authentication::Event.where(event: "person.linked").count).to eq(1)
      expect(Authentication::Event.where(event: "person.claimed").count).to eq(0)

      other_entry = create(:entity_entry, entity: entity, customer: customer)
      other = create(:user, customer: customer)
      described_class.link!(entry: other_entry, user_id: other.id, actor: actor, event: "person.claimed")
      expect(Authentication::Event.where(event: "person.claimed").count).to eq(1)
      expect(Authentication::Event.where(event: "person.linked").count).to eq(1)
    end
  end

  describe ".candidates" do
    it "returns active same-tenant users who are not already linked, matching the query" do
      alice = create(:user, customer: customer, first_name: "Alice", last_name: "Young", email: "alice.y@example.com")
      bob = create(:user, customer: customer, first_name: "Bob", last_name: "Adams", email: "bob.a@example.com")
      inactive = create(:user, :inactive, customer: customer, first_name: "Inez", last_name: "Young")
      foreign = create(:user, customer: other_customer, first_name: "Alice", last_name: "Young", email: "alice.other@example.com")
      taken = create(:user, customer: customer, first_name: "Taken", last_name: "Young", email: "taken.y@example.com")
      create(:entity_entry, entity: entity, customer: customer, user: taken)

      matches = described_class.candidates(entry: entry, query: "young")
      expect(matches).to include(alice)
      expect(matches).not_to include(bob, inactive, foreign, taken)

      by_email = described_class.candidates(entry: entry, query: "BOB.A@")
      expect(by_email).to include(bob)
      expect(by_email).not_to include(alice)

      blank = described_class.candidates(entry: entry, query: "  ", limit: 2)
      expect(blank.size).to eq(2)
      expect(blank).to eq(blank.sort_by { |row| [row.last_name, row.first_name] })
    end

    it "escapes LIKE wildcards in the query" do
      percent = create(:user, customer: customer, first_name: "100%", last_name: "Match", email: "pct@example.com")
      wildcard = create(:user, customer: customer, first_name: "100x", last_name: "Match", email: "wild@example.com")

      expect(described_class.candidates(entry: entry, query: "100%")).to include(percent)
      expect(described_class.candidates(entry: entry, query: "100%")).not_to include(wildcard)
    end
  end
end
