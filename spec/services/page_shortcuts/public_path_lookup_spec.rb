# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Request-scoped public path lookup" do
  let_it_be(:customer) { create(:customer, id: 81721200) }
  let_it_be(:other_customer) { create(:customer, id: 12345678) }
  let(:website) { create(:website, :published, customer: customer) }
  let!(:home) { create(:website_page, :home, :published, website: website) }
  let(:page) { create(:page, customer: customer, launched: true, audience_member: true, audience_public: true) }

  before { enable_module!("website", customer, name: "Website") }
  after { Current.reset }

  def count_queries
    count = 0
    callback = ->(_name, _start, _finish, _id, payload) do
      count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def render_links(pages)
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      2.times do # The same destinations occur in navigation and footer links.
        pages.each do |item|
          expect(Websites::Href.resolve(item.slug, customer_id: customer.id)).to eq("/offers/#{item.slug}")
        end
        expect(PageShortcuts::PublicPath.website_home(customer_id: customer.id)).to eq("/")
      end
    end
  end

  it "keeps presentation snapshots separate from live hostname selection" do
    target = create(:website_page, :published, website: website, slug: "pricing")
    PageShortcut.create!(customer_id: customer.id, path: "/plans", target: target)
    host = "live.example.test"
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      snapshot = Current.page_shortcuts_lookup
      expect(PageShortcuts::PublicPath.website_page(page: target, host: host)).to eq("/plans")
      binding = CustomDomainRecord.create!(hostname: host, customer_id: other_customer.id)
      expect(PageShortcuts::PublicPath.website_page(page: target, host: host)).to eq("/#{customer.id}/plans")
      binding.update!(customer_id: customer.id)
      expect(PageShortcuts::PublicPath.website_page(page: target, host: host)).to eq("/plans")
      binding.update!(hostname: "renamed.example.test", customer_id: other_customer.id)
      expect(PageShortcuts::PublicPath.website_page(page: target, host: host)).to eq("/plans")
      expect(PageShortcuts::PublicPath.website_page(page: target, host: binding.hostname)).to eq("/#{customer.id}/plans")
      binding.destroy!
      expect(PageShortcuts::PublicPath.website_page(page: target, host: "renamed.example.test")).to eq("/plans")
      expect(Current.page_shortcuts_lookup).to equal(snapshot)
    end
    expect(Current.page_shortcuts_lookup).to be_nil
  end

  it "keeps SQL bounded as the number of distinct navigation/footer destinations grows" do
    pages = Array.new(2) do |index|
      create(:website_page, :published, website: website, slug: "destination-#{index}").tap do |item|
        PageShortcut.create!(customer_id: customer.id, path: "/offers/#{item.slug}", target: item)
      end
    end
    small = count_queries { render_links(pages) }
    pages += Array.new(30) do |index|
      create(:website_page, :published, website: website, slug: "extra-#{index}").tap do |item|
        PageShortcut.create!(customer_id: customer.id, path: "/offers/#{item.slug}", target: item)
      end
    end
    large = count_queries { render_links(pages) }
    expect(large).to be <= small + 1
    expect(large).to be <= 7
    expect(Current.page_shortcuts_lookup).to be_nil
  end

  it "keeps mixed website and owned/shared UUID links bounded, including pages without aliases" do
    websites = []
    forms = []
    add_links = ->(count) do
      count.times do
        index = forms.size
        websites << create(:website_page, :published, website: website, slug: "mixed-#{index}")
        form = if index.even?
          create(:page, :shared, launched: true, audience_member: true, audience_public: true)
        else
          create(:page, customer: customer, launched: true, audience_member: true, audience_public: true)
        end
        alias_path = "/registrations/form-#{index}" if (index / 2).even?
        PageShortcut.create!(customer_id: customer.id, path: alias_path, target: form) if alias_path
        forms << [form.public_uuid, alias_path]
      end
    end
    render = -> do
      PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
        2.times do
          websites.each do |item|
            expect(Websites::Href.resolve(item.slug, customer_id: customer.id)).to eq("/#{item.slug}")
          end
          forms.each do |uuid, alias_path|
            canonical = "/#{customer.id}/page/#{uuid}"
            suffix = "?locale=zh-CN&tag=a&tag=b#registration"
            expect(Websites::Href.resolve("#{canonical}#{suffix}", customer_id: customer.id)).to eq("#{alias_path || canonical}#{suffix}")
          end
        end
      end
    end
    add_links.call(4)
    small = count_queries { render.call }
    add_links.call(32)
    expect_any_instance_of(Page).not_to receive(:reload_definition_from_head!)
    large = count_queries { render.call }
    expect(large).to be <= small + 1
    expect(large).to be <= 7
    expect(Current.page_shortcuts_lookup).to be_nil
  end

  it "does not borrow another tenant's UUID identity and preserves ineligible canonical links" do
    eligible = page
    foreign = create(:page, customer: other_customer, launched: true, audience_member: true, audience_public: true)
    private_page = create(:page, :for_member, customer: customer, launched: true)
    PageShortcut.create!(customer_id: customer.id, path: "/register", target: eligible)
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      identity = Current.page_shortcuts_lookup.public_page_for_uuid(eligible.public_uuid)
      expect(identity).to be_frozen
      expect(identity.public_uuid).to be_frozen
      expect(PageShortcuts::PublicPath.public_page_uuid(uuid: eligible.public_uuid, customer_id: customer.id)).to eq("/register")
      [foreign, private_page].each do |target|
        path = "/#{customer.id}/page/#{target.public_uuid}"
        expect(Websites::Href.resolve(path, customer_id: customer.id)).to eq(path)
        expect(PageShortcuts::PublicPath.public_page_uuid(uuid: target.public_uuid, customer_id: customer.id)).to be_nil
      end
    end
    eligible.update!(launched: false)
    expect(PageShortcuts::PublicPath.public_page_uuid(uuid: eligible.public_uuid, customer_id: customer.id)).to be_nil
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      expect(PageShortcuts::PublicPath.public_page_uuid(uuid: eligible.public_uuid, customer_id: customer.id)).to be_nil
    end
  end

  it "keeps the snapshot immutable, tenant-specific and scoped even when rendering raises" do
    shared = create(:page, :shared, launched: true, audience_member: true, audience_public: true)
    mine = PageShortcut.create!(customer_id: customer.id, path: "/join", target: shared)
    other = PageShortcut.create!(customer_id: other_customer.id, path: "/foreign-join", target: shared)
    expect do
      PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
        lookup = Current.page_shortcuts_lookup
        expect(lookup).to be_frozen
        expect(lookup.home_page).to be_frozen
        expect(lookup.home_page.slug).to be_frozen
        expect(lookup.shortcut_at(mine.path)).to be_frozen
        expect(lookup.alias_path("Page", shared.id)).to be_frozen
        expect(PageShortcuts::PublicPath.public_page(page: shared, customer_id: customer.id)).to eq(mine.path)
        expect(PageShortcuts::PublicPath.public_page(page: shared, customer_id: other_customer.id)).to eq("/#{other_customer.id}#{other.path}")
        PageShortcuts::PublicPath.with_lookup(customer_id: other_customer.id) do
          expect(Current.page_shortcuts_lookup.customer_id).to eq(other_customer.id)
        end
        expect(Current.page_shortcuts_lookup).to equal(lookup)
        raise "render failed"
      end
    end.to raise_error("render failed")
    expect(Current.page_shortcuts_lookup).to be_nil
  end

  it "refreshes alias/publication changes in the next scope and keeps unscoped service calls fresh" do
    target = create(:website_page, :published, website: website, slug: "pricing")
    mapping = PageShortcut.create!(customer_id: customer.id, path: "/old-plans", target: target)
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      expect(PageShortcuts::PublicPath.website_slug(slug: target.slug, customer_id: customer.id)).to eq("/old-plans")
      mapping.update!(path: "/new-plans")
      expect(PageShortcuts::PublicPath.website_page(page: target)).to eq("/old-plans")
    end
    expect(PageShortcuts::PublicPath.website_page(page: target)).to eq("/new-plans")
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      expect(PageShortcuts::PublicPath.website_page(page: target)).to eq("/new-plans")
    end
    website.update!(published: false)
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      expect(PageShortcuts::PublicPath.website_page(page: target)).to eq("/pricing")
    end
  end

  it "retains root overrides, reserved fallback and unpublished automatic collision rules in the snapshot" do
    root = PageShortcut.create!(customer_id: customer.id, path: "/", target: page)
    reserved = create(:website_page, :published, website: website, slug: "auth")
    create(:website_page, website: website, slug: "taken", published: false)
    PageShortcut.create!(customer_id: customer.id, path: "/taken", target: page)
    PageShortcut.create!(customer_id: customer.id, path: "/z-join", target: page)
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      expect(PageShortcuts::PublicPath.website_home(customer_id: customer.id)).to eq("/#{customer.id}/site")
      expect(PageShortcuts::PublicPath.public_page(page: page, customer_id: customer.id)).to eq(root.path)
      expect(PageShortcuts::PublicPath.website_page(page: reserved)).to eq("/#{customer.id}/site/auth")
    end
    root.destroy!
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id) do
      expect(PageShortcuts::PublicPath.public_page(page: page, customer_id: customer.id)).to eq("/z-join")
    end
  end
end
