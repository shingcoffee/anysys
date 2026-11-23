# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncements::Resolver do
  let(:now) { Time.zone.parse("2026-08-29 12:00:00") }
  let(:customer) { create(:customer) }

  def resolve(customer_id = customer.id, **opts)
    described_class.for_customer(customer_id, now: now, **opts)
  end

  it "hides a published row whose starts_at is in the future" do
    create(:platform_announcement, :published, :all_customers, starts_at: now + 1.hour)
    expect(resolve).to eq([])
  end

  it "hides a published row whose ends_at is in the past" do
    create(:platform_announcement, :published, :all_customers, ends_at: now)
    expect(resolve).to eq([])
  end

  it "includes a published row with a nil window" do
    announcement = create(:platform_announcement, :published, :all_customers)
    expect(resolve).to eq([ announcement ])
  end

  it "excludes drafts" do
    create(:platform_announcement, :draft, :all_customers)
    expect(resolve).to eq([])
  end

  it "includes a selected announcement only for customers matching target_rules" do
    other = create(:customer)
    announcement = create(
      :platform_announcement, :published, :selected,
      target_rules: {
        "type" => "group",
        "joins" => [],
        "conditions" => [
          { "field" => "id", "operator" => "equals", "value" => customer.id.to_s }
        ]
      }
    )

    expect(resolve(customer.id)).to eq([ announcement ])
    expect(resolve(other.id)).to eq([])
  end

  it "includes a later customer that matches selected target_rules" do
    create(
      :platform_announcement, :published, :selected,
      target_rules: {
        "type" => "group",
        "joins" => [],
        "conditions" => [
          { "field" => "tier", "operator" => "equals", "value" => "premium" }
        ]
      }
    )
    later = create(:customer, :premium)
    expect(resolve(later.id).size).to eq(1)
  end

  it "includes a customer created after an all-audience publish" do
    announcement = create(:platform_announcement, :published, :all_customers)
    later = create(:customer)
    expect(resolve(later.id)).to eq([ announcement ])
  end

  it "excludes dismissed ids" do
    shown = create(:platform_announcement, :published, :all_customers)
    hidden = create(:platform_announcement, :published, :all_customers)
    hidden.update_column(:created_at, shown.created_at + 1.second)

    expect(resolve(dismissed_ids: [ hidden.id ])).to eq([ shown ])
  end

  it "orders live rows by created_at DESC, id DESC" do
    older = create(:platform_announcement, :published, :all_customers)
    newer = create(:platform_announcement, :published, :all_customers)
    older.update_column(:created_at, now - 2.days)
    newer.update_column(:created_at, now - 1.day)

    expect(resolve.map(&:id)).to eq([ newer.id, older.id ])
  end

  describe "query budget" do
    def id_rules(id)
      {
        "type" => "group",
        "joins" => [],
        "conditions" => [ { "field" => "id", "operator" => "equals", "value" => id.to_s } ]
      }
    end

    it "evaluates many segments in a fixed number of queries (no N+1)" do
      customer # materialize before counting
      5.times { create(:platform_announcement, :published, :selected, target_rules: id_rules(customer.id)) }
      warm = count_queries { resolve }

      5.times { create(:platform_announcement, :published, :selected, target_rules: id_rules(customer.id)) }
      grown = count_queries { resolve }

      expect(grown).to eq(warm)
      expect(grown).to be <= 2
    end

    it "skips the segment query entirely when every notice targets all customers" do
      customer # materialize before counting
      3.times { create(:platform_announcement, :published, :all_customers) }

      expect(count_queries { resolve }).to eq(1)
    end
  end

  describe ".for_viewer" do
    let(:admin) { create(:user, :admin, customer: customer) }

    it "hides announcements the viewer has already dismissed" do
      kept      = create(:platform_announcement, :published, :all_customers)
      dismissed = create(:platform_announcement, :published, :all_customers)
      PlatformAnnouncementDismissal.record!(announcement: dismissed, user_id: admin.id, customer_id: customer.id)

      expect(described_class.for_viewer(user: admin, customer_id: customer.id, now: now)).to eq([ kept ])
    end

    it "shows everything live to a viewer with no dismissals" do
      announcement = create(:platform_announcement, :published, :all_customers)

      expect(described_class.for_viewer(user: admin, customer_id: customer.id, now: now)).to eq([ announcement ])
    end

    it "tolerates a nil viewer" do
      announcement = create(:platform_announcement, :published, :all_customers)

      expect(described_class.for_viewer(user: nil, customer_id: customer.id, now: now)).to eq([ announcement ])
    end
  end

  describe "candidate bound" do
    it "never considers more than CANDIDATE_LIMIT live notices" do
      (described_class::CANDIDATE_LIMIT + 3).times { create(:platform_announcement, :published, :all_customers) }

      expect(resolve.size).to eq(described_class::CANDIDATE_LIMIT)
    end
  end
end
