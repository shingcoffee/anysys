# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlatformAnnouncements::Activities::Save do
  def id_rules(customer_id)
    {
      "type" => "group",
      "joins" => [],
      "conditions" => [
        { "field" => "id", "operator" => "equals", "value" => customer_id.to_s }
      ]
    }
  end

  def valid_params(overrides = {})
    {
      title: "Notice",
      body_en: "English body",
      body_zh: "中文正文",
      severity: "warning",
      status: "published",
      audience: "all",
      link_url: "https://example.com/more",
      starts_at: nil,
      ends_at: nil,
      target_rules: {}
    }.merge(overrides)
  end

  it "persists a valid announcement" do
    record = PlatformAnnouncement.new
    result = described_class.call(record: record, params: valid_params)

    expect(result.success?).to be true
    expect(result.model).to be_persisted
    expect(result.model).to have_attributes(
      title: "Notice",
      severity: "warning",
      status: "published",
      audience: "all",
      link_url: "https://example.com/more"
    )
    expect(result.model.target_rules).to eq({})
  end

  it "persists target_rules when audience is selected" do
    customer = create(:customer)
    rules = id_rules(customer.id)
    record = PlatformAnnouncement.new
    result = described_class.call(
      record: record,
      params: valid_params(audience: "selected", target_rules: rules)
    )

    expect(result.success?).to be true
    expect(result.model.target_rules).to eq(rules)
  end

  it "parses target_rules_json from the form hidden field" do
    customer = create(:customer)
    rules = id_rules(customer.id)
    record = PlatformAnnouncement.new
    result = described_class.call(
      record: record,
      params: valid_params(audience: "selected", target_rules_json: rules.to_json).except(:target_rules)
    )

    expect(result.success?).to be true
    expect(result.model.target_rules).to eq(rules)
  end

  it "clears target_rules when audience is all" do
    customer = create(:customer)
    record = PlatformAnnouncement.new
    result = described_class.call(
      record: record,
      params: valid_params(audience: "all", target_rules: id_rules(customer.id))
    )

    expect(result.success?).to be true
    expect(result.model.target_rules).to eq({})
  end

  it "replaces target_rules on update" do
    kept = create(:customer)
    dropped = create(:customer)
    record = create(:platform_announcement, :published, :selected, target_rules: id_rules(dropped.id))

    result = described_class.call(
      record: record,
      params: valid_params(audience: "selected", target_rules: id_rules(kept.id))
    )

    expect(result.success?).to be true
    expect(record.reload.target_rules).to eq(id_rules(kept.id))
  end

  it "fails when selected has no usable conditions and does not persist" do
    record = PlatformAnnouncement.new
    result = described_class.call(
      record: record,
      params: valid_params(audience: "selected", target_rules: {})
    )

    expect(result.success?).to be false
    expect(result.errors).to be_present
    expect(result.model).to eq(record)
    expect(PlatformAnnouncement.count).to eq(0)
  end

  it "fails on malformed target_rules_json and does not persist" do
    record = PlatformAnnouncement.new
    result = described_class.call(
      record: record,
      params: valid_params(audience: "selected").except(:target_rules).merge(target_rules_json: "{not json")
    )

    expect(result.success?).to be false
    expect(result.messages).to include(I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
    expect(PlatformAnnouncement.count).to eq(0)
  end

  it "fails on an invalid URL and does not persist" do
    record = PlatformAnnouncement.new
    result = described_class.call(
      record: record,
      params: valid_params(link_url: "javascript:alert(1)")
    )

    expect(result.success?).to be false
    expect(result.errors).to have_key(:link_url)
    expect(result.messages.join(" ")).to match(/link.url|is invalid/i)
    expect(PlatformAnnouncement.count).to eq(0)
  end

  it "fails on an http(s)-prefixed javascript payload and does not persist" do
    record = PlatformAnnouncement.new
    result = described_class.call(
      record: record,
      params: valid_params(link_url: "https://example.com\njavascript:alert(1)")
    )

    expect(result.success?).to be false
    expect(result.errors).to have_key(:link_url)
    expect(PlatformAnnouncement.count).to eq(0)
  end

  describe "left_live_at" do
    let(:now) { Time.zone.parse("2026-08-31 12:00:00") }

    it "stamps left_live_at when a live announcement is unpublished" do
      record = create(:platform_announcement, :published, :all_customers)

      travel_to(now) do
        result = described_class.call(record: record, params: valid_params(status: "draft"))
        expect(result.success?).to be true
      end

      expect(record.reload.left_live_at).to be_within(1.second).of(now)
    end

    it "clears left_live_at when republished into the live window" do
      record = create(:platform_announcement, :draft, :all_customers, left_live_at: now - 1.day)

      result = described_class.call(record: record, params: valid_params(status: "published"))

      expect(result.success?).to be true
      expect(record.reload.left_live_at).to be_nil
    end

    it "does not stamp left_live_at when a scheduled announcement is unpublished" do
      record = create(:platform_announcement, :published, :all_customers, starts_at: now + 1.day)

      travel_to(now) do
        result = described_class.call(
          record: record,
          params: valid_params(status: "draft", starts_at: now + 1.day)
        )
        expect(result.success?).to be true
      end

      expect(record.reload.left_live_at).to be_nil
    end

    it "clears left_live_at when a previously-live draft is republished as scheduled" do
      record = create(:platform_announcement, :draft, :all_customers, left_live_at: now - 1.day)

      travel_to(now) do
        result = described_class.call(
          record: record,
          params: valid_params(status: "published", starts_at: now + 1.day)
        )
        expect(result.success?).to be true
      end

      expect(record.reload.left_live_at).to be_nil
    end
  end

  describe "live websocket fan-out" do
    let(:customer) { create(:customer) }
    let!(:admin) { create(:user, :admin, customer: customer) }

    before do
      allow(Notifications::Stream).to receive(:sync_announcement!)
      allow(Notifications::Stream).to receive(:announcement_recipients).and_return(Authentication::User.none)
    end

    it "syncs after a successful live publish" do
      allow(Notifications::Stream).to receive(:sync_announcement!).and_call_original
      allow(Notifications::Stream).to receive(:broadcast_announcement!)
      allow(Notifications::Stream).to receive(:broadcast_announcement_removed!)
      allow(Notifications::BroadcastAnnouncementJob).to receive(:schedule)

      record = PlatformAnnouncement.new
      result = described_class.call(record: record, params: valid_params)

      expect(result.success?).to be true
      expect(Notifications::Stream).to have_received(:sync_announcement!).with(
        record, previous_users: []
      )
      expect(Notifications::Stream).to have_received(:broadcast_announcement!).with(record)
    end

    it "does not broadcast a draft" do
      allow(Notifications::Stream).to receive(:sync_announcement!).and_call_original
      allow(Notifications::Stream).to receive(:broadcast_announcement!)
      allow(Notifications::Stream).to receive(:broadcast_announcement_removed!)
      allow(Notifications::BroadcastAnnouncementJob).to receive(:schedule)

      record = PlatformAnnouncement.new
      described_class.call(record: record, params: valid_params(status: "draft"))

      expect(Notifications::Stream).not_to have_received(:broadcast_announcement!)
    end

    it "notifies previous recipients when a live notice is unpublished" do
      allow(Notifications::Stream).to receive(:announcement_recipients).and_return([ admin ])
      allow(Notifications::Stream).to receive(:sync_announcement!).and_call_original
      allow(Notifications::Stream).to receive(:broadcast_announcement!)
      allow(Notifications::Stream).to receive(:broadcast_announcement_removed!)
      allow(Notifications::BroadcastAnnouncementJob).to receive(:schedule)

      record = create(:platform_announcement, :published, :all_customers)
      described_class.call(record: record, params: valid_params(status: "draft"))

      expect(Notifications::Stream).to have_received(:broadcast_announcement_removed!).with(
        record, users: [ admin ]
      )
      expect(Notifications::Stream).not_to have_received(:broadcast_announcement!)
    end
  end
end
