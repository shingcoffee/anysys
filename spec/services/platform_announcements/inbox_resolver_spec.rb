# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncements::InboxResolver do
  let(:now) { Time.zone.parse("2026-08-31 12:00:00") }
  let(:customer) { create(:customer) }

  def resolve(customer_id = customer.id, **opts)
    described_class.for_customer(customer_id, now: now, **opts)
  end

  def inbox(customer_id = customer.id)
    resolve(customer_id).announcements
  end

  it "includes a live all-audience announcement" do
    announcement = create(:platform_announcement, :published, :all_customers)

    expect(inbox).to eq([ announcement ])
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

    expect(inbox(customer.id)).to eq([ announcement ])
    expect(inbox(other.id)).to eq([])
  end

  it "excludes a selected announcement that does not match the viewer" do
    create(
      :platform_announcement, :published, :selected,
      target_rules: {
        "type" => "group",
        "joins" => [],
        "conditions" => [
          { "field" => "id", "operator" => "equals", "value" => create(:customer).id.to_s }
        ]
      }
    )

    expect(inbox).to eq([])
  end

  it "hides a published row whose starts_at is in the future" do
    create(:platform_announcement, :published, :all_customers, starts_at: now + 1.hour)
    expect(inbox).to eq([])
  end

  it "includes a published row that ended within 7 days" do
    announcement = create(:platform_announcement, :published, :all_customers, ends_at: now - 3.days)
    expect(inbox).to eq([ announcement ])
  end

  it "excludes a published row that ended more than 7 days ago" do
    create(:platform_announcement, :published, :all_customers, ends_at: now - 8.days)
    expect(inbox).to eq([])
  end

  it "includes an unpublished-from-live announcement for 7 days" do
    announcement = create(:platform_announcement, :draft, :all_customers, left_live_at: now - 3.days)
    expect(inbox).to eq([ announcement ])
  end

  it "excludes an unpublished-from-live announcement older than 7 days" do
    create(:platform_announcement, :draft, :all_customers, left_live_at: now - 8.days)
    expect(inbox).to eq([])
  end

  it "includes a discarded announcement for 7 days" do
    announcement = create(:platform_announcement, :published, :all_customers)
    announcement.update_columns(deleted_at: now - 2.days, left_live_at: now - 2.days)

    expect(inbox).to eq([ announcement ])
  end

  it "excludes a discarded announcement older than 7 days" do
    announcement = create(:platform_announcement, :published, :all_customers)
    announcement.update_columns(deleted_at: now - 8.days, left_live_at: now - 8.days)

    expect(inbox).to eq([])
  end

  it "does not revive a discarded-while-live row when its original ends_at later falls in the 7-day window" do
    announcement = create(:platform_announcement, :published, :all_customers, ends_at: now - 1.day)
    announcement.update_columns(deleted_at: now - 20.days, left_live_at: now - 20.days)

    expect(inbox).to eq([])
  end

  it "includes a customer created after an all-audience publish" do
    announcement = create(:platform_announcement, :published, :all_customers)
    later = create(:customer)

    expect(inbox(later.id)).to eq([ announcement ])
  end

  it "does not honour banner dismissals" do
    announcement = create(:platform_announcement, :published, :all_customers)
    admin = create(:user, :admin, customer: customer)
    PlatformAnnouncementDismissal.record!(
      announcement: announcement, user_id: admin.id, customer_id: customer.id
    )

    expect(inbox).to eq([ announcement ])
    expect(
      described_class.for_viewer(user: admin, customer_id: customer.id, now: now).announcements
    ).to eq([ announcement ])
  end

  it "orders candidates by created_at DESC, id DESC" do
    older = create(:platform_announcement, :published, :all_customers)
    newer = create(:platform_announcement, :published, :all_customers)
    older.update_column(:created_at, now - 2.days)
    newer.update_column(:created_at, now - 1.day)

    expect(inbox.map(&:id)).to eq([ newer.id, older.id ])
  end

  describe ".for_viewer" do
    let(:admin) { create(:user, :admin, customer: customer) }

    it "returns read ids without consulting dismissals" do
      unread = create(:platform_announcement, :published, :all_customers)
      read = create(:platform_announcement, :published, :all_customers)
      dismissed = create(:platform_announcement, :published, :all_customers)
      unread.update_column(:created_at, now - 3.days)
      read.update_column(:created_at, now - 2.days)
      dismissed.update_column(:created_at, now - 1.day)

      PlatformAnnouncementRead.record!(announcement: read, user_id: admin.id, customer_id: customer.id)
      PlatformAnnouncementDismissal.record!(
        announcement: dismissed, user_id: admin.id, customer_id: customer.id
      )

      result = described_class.for_viewer(user: admin, customer_id: customer.id, now: now)

      expect(result.announcements.map(&:id)).to eq([ dismissed.id, read.id, unread.id ])
      expect(result.read_ids).to eq([ read.id ])
    end

    it "tolerates a nil viewer" do
      announcement = create(:platform_announcement, :published, :all_customers)

      result = described_class.for_viewer(user: nil, customer_id: customer.id, now: now)

      expect(result.announcements).to eq([ announcement ])
      expect(result.read_ids).to eq([])
    end
  end

  describe "query budget" do
    def id_rules(id)
      {
        "type" => "group",
        "joins" => [],
        "conditions" => [ { "field" => "id", "operator" => "equals", "value" => id.to_s } ]
      }
    end

    let(:admin) { create(:user, :admin, customer: customer) }

    it "evaluates many segments in a fixed number of queries (no N+1)" do
      customer
      admin
      5.times { create(:platform_announcement, :published, :selected, target_rules: id_rules(customer.id)) }
      warm = count_queries { described_class.for_viewer(user: admin, customer_id: customer.id, now: now) }

      5.times { create(:platform_announcement, :published, :selected, target_rules: id_rules(customer.id)) }
      grown = count_queries { described_class.for_viewer(user: admin, customer_id: customer.id, now: now) }

      expect(grown).to eq(warm)
      expect(grown).to be <= 3
    end

    it "uses two queries for an all-audience inbox (candidates + reads)" do
      customer
      admin
      3.times { create(:platform_announcement, :published, :all_customers) }

      expect(count_queries { described_class.for_viewer(user: admin, customer_id: customer.id, now: now) }).to eq(2)
    end
  end

  describe "candidate bound" do
    it "never considers more than CANDIDATE_LIMIT notices" do
      (described_class::CANDIDATE_LIMIT + 3).times { create(:platform_announcement, :published, :all_customers) }

      expect(inbox.size).to eq(described_class::CANDIDATE_LIMIT)
    end
  end
end
