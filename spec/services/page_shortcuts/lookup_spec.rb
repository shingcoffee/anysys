# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::Lookup do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:website) { create(:website, :published, customer: customer) }
  let(:page) { create(:page, :for_member, :for_public, customer: customer, launched: true, name: "Registration") }

  before { enable_module!("website", customer, name: "Website") }
  after { Current.reset }

  def mapping(target, path: "/join", customer_id: customer.id)
    PageShortcut.create!(customer_id: customer_id, path: path, target: target)
  end

  it "reads saved owned/shared names and unpublished website titles without loading Page definitions" do
    owned = page
    shared = create(:page, :shared, :for_member, launched: false, name: "Shared draft")
    deleted = create(:page, customer: customer, name: "Deleted form")
    deleted.update!(status: :inactive)
    private_page = create(:page, :for_member, customer: customer, name: "Private form")
    offline = create(:website_page, website: website, slug: "offline", title: "Offline website page")
    targets = [owned, shared, deleted, private_page, offline]
    mappings = targets.each_with_index.map { |target, index| mapping(target, path: "/saved-#{index}") }
    expect_any_instance_of(Page).not_to receive(:reload_definition_from_head!)
    expect(Page).not_to receive(:accessible)
    Current.customer = other_customer

    lookup = described_class.new(customer_id: customer.id, include_titles: true)

    targets.each do |target|
      title = target.is_a?(WebsitePage) ? target.title : target.name
      expect(lookup.target_title(target.class.name, target.id)).to eq(title)
      expect(lookup.target_title(target.class.name, target.id)).to be_frozen
    end
    expect(lookup.shortcut_available?(mappings.first)).to be(true)
    mappings.drop(1).each { |shortcut| expect(lookup.shortcut_available?(shortcut)).to be(false) }
    expect(Current.customer).to eq(other_customer)
  end

  it "returns nil for missing, foreign and unsaved Page identities" do
    foreign = create(:page, :for_member, :for_public, customer: other_customer, launched: true)
    unsaved = page
    wrong_site = create(:website, :published, customer: other_customer)
    mismatched = create(:website_page, :published, website: wrong_site, customer: customer, slug: "mismatch")
    foreign_mapping = mapping(foreign, path: "/foreign")
    missing_mapping = PageShortcut.create!(customer_id: customer.id, path: "/missing", target_type: "Page", target_id: 999999999)
    mapping(mismatched, path: "/mismatch")

    lookup = described_class.new(customer_id: customer.id, include_titles: true)

    expect(lookup.target_title("Page", foreign.id)).to be_nil
    expect(lookup.target_title("Page", missing_mapping.target_id)).to be_nil
    expect(lookup.target_title("Page", unsaved.id)).to be_nil
    expect(lookup.target_title("WebsitePage", mismatched.id)).to be_nil
    expect(lookup.target_title("Customer", customer.id)).to be_nil
    expect(lookup.shortcut_available?(foreign_mapping)).to be(false)
    expect(lookup.shortcut_available?(missing_mapping)).to be(false)
  end

  it "uses the same canonical path, tenant, eligibility and collision checks for management and aliases" do
    target = page
    inner = create(:website_page, :published, website: website, slug: "pricing")
    create(:website_page, website: website, slug: "reserved-slot", published: false)
    root = mapping(target, path: "/")
    good = mapping(target, path: "/z-join")
    same_page = mapping(inner, path: "/pricing")
    unavailable = [
      mapping(target, path: "/admin"),
      mapping(target, path: "/trailing/"),
      PageShortcut.new(customer_id: customer.id, path: "no-leading-slash", target: target),
      mapping(target, path: "/reserved-slot"),
      mapping(target, path: "/foreign-tenant", customer_id: other_customer.id),
      PageShortcut.new(customer_id: customer.id, target: target)
    ]
    lookup = described_class.new(customer_id: customer.id)

    [root, good, same_page].each do |shortcut|
      expect(shortcut).not_to receive(:target)
      expect(lookup.shortcut_available?(shortcut)).to be(true)
      expect(lookup.shortcut_available?(lookup.shortcut_at(shortcut.path))).to be(true)
    end
    unavailable.each { |shortcut| expect(lookup.shortcut_available?(shortcut)).to be(false) }
    expect(lookup.alias_path("Page", target.id)).to eq("/")
    expect(lookup.alias_path("WebsitePage", inner.id)).to eq("/pricing")
  end

  it "captures immutable titles and host scope while live eligibility remains fresh" do
    shortcut = mapping(page)
    binding = CustomDomainRecord.create!(customer_id: customer.id, hostname: "snapshot.example.test")
    lookup = described_class.new(customer_id: customer.id, host: binding.hostname, include_titles: true)
    page.update!(name: "Renamed", launched: false)
    binding.update!(customer_id: other_customer.id)

    expect(lookup).to be_frozen
    expect(lookup.host).to be_frozen
    expect(lookup.host_customer_id).to eq(customer.id)
    expect(lookup.target_title("Page", page.id)).to eq("Registration")
    expect(lookup.shortcut_available?(shortcut)).to be(true)
    expect(PageShortcuts::TargetEligibility.eligible?(shortcut, customer_id: customer.id)).to be(false)
    fresh = described_class.new(customer_id: customer.id, host: lookup.host, include_titles: true)
    expect(fresh.host_customer_id).to eq(other_customer.id)
    expect(fresh.target_title("Page", page.id)).to eq("Renamed")
    expect(fresh.shortcut_available?(shortcut)).to be(false)
  end

  it "adds only one saved-ID Page name query in title mode and keeps management reads bounded" do
    add_targets = ->(count) do
      count.times do
        form = create(:page, :for_member, :for_public, customer: customer, launched: true)
        mapping(form, path: "/form-#{form.id}")
      end
    end
    render = ->(include_titles) do
      lookup = described_class.new(customer_id: customer.id, host: "management.example.test", include_titles: include_titles)
      PageShortcut.for_customer(customer.id).each do |shortcut|
        expect(lookup.shortcut_available?(shortcut)).to be(true)
        if include_titles
          expect(lookup.target_title(shortcut.target_type, shortcut.target_id)).to be_present
        else
          expect(lookup.target_title(shortcut.target_type, shortcut.target_id)).to be_nil
        end
      end
    end
    add_targets.call(2)
    ordinary = count_queries { render.call(false) }
    small = count_queries { render.call(true) }
    add_targets.call(30)
    expect_any_instance_of(Page).not_to receive(:reload_definition_from_head!)
    large = count_queries { render.call(true) }

    expect(small).to eq(ordinary + 1)
    expect(ordinary).to be <= 8 # Public lookup <= 7; the list adds one.
    expect(large).to eq(small)
    expect(large).to be <= 9 # Lookup <= 8; the management list itself adds one.
  end

  it "limits title reads to saved Page IDs and skips them in ordinary public lookups" do
    saved = mapping(page)
    create(:page, customer: customer, name: "Unmapped")
    statements = []
    callback = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      described_class.new(customer_id: customer.id)
    end
    expect(statements.grep(/SELECT.*"pages"\."name"/)).to be_empty

    statements.clear
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      described_class.new(customer_id: customer.id, include_titles: true)
    end
    title_reads = statements.grep(/SELECT.*"pages"\."name"/)
    expect(title_reads.size).to eq(1)
    expect(title_reads.first).to include('"pages"."id" =', '"pages"."customer_id"')
    expect(title_reads.first).not_to include('"pages"."status"')
    expect(saved.target_id).to eq(page.id)
  end
end
