# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Announcement audience persistence and resolution" do
  let!(:customer) { create(:customer, name: "Acme", tier: :premium) }
  let!(:other) { create(:customer, name: "Other", tier: :basic) }

  def leaf(field, operator, value = "")
    { "field" => field, "operator" => operator, "value" => value }
  end

  def group(*conditions, joins: nil)
    { "type" => "group", "conditions" => conditions, "joins" => joins || Array.new([conditions.size - 1, 0].max, "AND") }
  end

  def id_rules(id)
    group(leaf("id", "equals", id.to_s))
  end

  def save_selected(rules, record: PlatformAnnouncement.new)
    PlatformAnnouncements::Activities::Save.call(record: record, params: {
      title: "Targeted notice", body_en: "English", body_zh: "中文", severity: "warning",
      status: "published", audience: "selected", target_rules_json: rules.to_json
    })
  end

  [
    ["id", "greater_than", "garbage"],
    ["id", "not_equals", "2.5"],
    ["id", "equals", 2.5],
    ["id", "equals", "9223372036854775808"],
    ["tier", "not_equals", "unknown"],
    ["industry", "equals", "-1"],
    ["created_at", "after", "2026-02-30"],
    ["created_at", "before", "2026-10-11T25:90:00Z"],
    ["created_at", "equals", "2026-10-11"],
    ["name", "greater_than", "Acme"],
    ["name", "contains", { "value" => "Acme" }],
    ["tier", "contains", "premium"],
    ["encrypted_password", "equals", "x"]
  ].each do |field, operator, value|
    it "rejects #{field}/#{operator}/#{value.inspect} without creating a notice or widening an AND audience" do
      rules = group(leaf("name", "contains", ""), leaf(field, operator, value))
      result = nil

      expect { result = save_selected(rules) }.not_to change(PlatformAnnouncement, :count)
      expect(result).not_to be_success
      expect(result.messages).to include(I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
      expect(PlatformAnnouncements::TargetRules.parse(rules)).to be_malformed
      expect(PlatformAnnouncements::CustomerQuery.call(rules: rules)).to be_empty
    end
  end

  it "preserves stored content when a selected audience edit is invalid" do
    record = create(:platform_announcement, :selected, target_rules: id_rules(customer.id))
    prior = record.attributes.deep_dup

    expect(save_selected(group(leaf("id", "greater_than", "garbage")), record: record)).not_to be_success
    expect(record.reload.attributes).to eq(prior)
  end

  it "accepts valid enum and numeric comparisons and ISO timestamps" do
    rules = group(
      leaf("tier", "equals", "premium"),
      leaf("id", "equals", customer.id),
      leaf("created_at", "after", "2020-01-01T00:00:00Z")
    )

    expect(save_selected(rules)).to be_success
    expect(PlatformAnnouncements::CustomerQuery.call(rules: rules).ids).to eq([customer.id])
    expect(PlatformAnnouncements::CustomerQuery.call(rules: group(leaf("tier", "equals", Customer.tiers.fetch("premium")))).ids).to eq([customer.id])
  end

  it "handles enum presence using integer storage rather than an empty string comparison" do
    expect(PlatformAnnouncements::CustomerQuery.call(rules: group(leaf("tier", "is_present"))).ids).to include(customer.id, other.id)
    expect(PlatformAnnouncements::CustomerQuery.call(rules: group(leaf("tier", "is_blank")))).to be_empty
  end

  it "treats SQL LIKE wildcard characters as literal audience text" do
    literal = create(:customer, name: "Acme_100%", contact: "wildcard-audience@example.com")
    create(:customer, name: "AcmeX100Y")

    rules = group(leaf("name", "contains", "_100%"))
    expect(PlatformAnnouncements::CustomerQuery.call(rules: rules).ids).to eq([literal.id])
  end

  it "rejects malformed groups, join alignment, nested empty groups and non-object JSON" do
    [
      { "conditions" => "not a list" },
      group(leaf("id", "equals", customer.id.to_s), leaf("name", "equals", "Acme"), joins: []),
      group(leaf("id", "equals", customer.id.to_s), leaf("name", "equals", "Acme"), joins: ["XOR"]),
      group(group, leaf("name", "equals", "Acme")),
      [1, 2], false
    ].each do |rules|
      expect(PlatformAnnouncements::TargetRules.parse(rules.to_json)).to be_malformed
      expect(PlatformAnnouncements::CustomerQuery.call(rules: rules)).to be_empty
    end
  end

  it "keeps an empty audience distinct from malformed rules and never selects everyone" do
    expect(PlatformAnnouncements::TargetRules.parse("{}")).not_to be_malformed
    expect(PlatformAnnouncements::TargetRules.parse("{}")).not_to be_usable
    expect(save_selected({})).not_to be_success
  end

  it "rejects excessive depth without permitting the valid sibling condition" do
    nested = id_rules(customer.id)
    (PlatformAnnouncements::CustomerQuery::MAX_DEPTH + 1).times { nested = group(nested) }
    expect(PlatformAnnouncements::TargetRules.parse(group(leaf("id", "is_present"), nested))).to be_malformed
  end

  it "enforces semantic validation on direct model writes" do
    record = build(:platform_announcement, :selected, target_rules: group(leaf("tier", "not_equals", "unknown")))
    expect(record.save).to be(false)
    expect(record.errors[:base]).to include(I18n.t("maint_platform.announcements.form.errors.target_rules_invalid"))
  end

  it "finds a tenant's notice after more than one batch of newer unrelated notices in banner and inbox" do
    notice = create(:platform_announcement, :published, :selected, target_rules: id_rules(customer.id))
    stamp = Time.current.change(usec: 0)
    notice.update_column(:created_at, stamp)
    newer = create_list(:platform_announcement, PlatformAnnouncements::AudienceResolver::BATCH_SIZE + 5,
      :published, :selected, target_rules: id_rules(other.id))
    PlatformAnnouncement.where(id: newer.map(&:id)).update_all(created_at: stamp)

    expect(PlatformAnnouncements::Resolver.for_customer(customer.id).map(&:id)).to eq([notice.id])
    expect(PlatformAnnouncements::InboxResolver.for_customer(customer.id).announcements.map(&:id)).to eq([notice.id])
  end

  it "keeps an older critical notice ahead of the relevant banner cap" do
    critical = create(:platform_announcement, :published, :critical, :selected, target_rules: id_rules(customer.id))
    critical.update_column(:created_at, 2.days.ago)
    create_list(:platform_announcement, PlatformAnnouncements::Resolver::CANDIDATE_LIMIT + 5, :published, :info)

    rows = PlatformAnnouncements::Resolver.for_customer(customer.id)
    expect(rows.size).to eq(PlatformAnnouncements::Resolver::CANDIDATE_LIMIT)
    expect(rows.first).to eq(critical)
  end

  it "does not deliver an imported malformed segment that was stored before strict validation" do
    notice = create(:platform_announcement, :published, :selected, target_rules: id_rules(customer.id))
    notice.update_column(:target_rules, group(leaf("id", "greater_than", "garbage")))

    expect(PlatformAnnouncements::Resolver.for_customer(customer.id)).to be_empty
    expect(PlatformAnnouncements::InboxResolver.for_customer(customer.id).announcements).to be_empty
  end
end
