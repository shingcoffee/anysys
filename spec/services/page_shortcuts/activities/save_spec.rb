# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::Activities::Save do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:page) { create(:page, customer: customer, launched: true, audience_member: true, audience_public: true) }
  let(:website) { create(:website, :published, customer: customer) }
  let(:website_page) { create(:website_page, :published, website: website, customer: customer, slug: "pricing") }
  let(:shortcut) { PageShortcut.new }

  after { Current.reset }

  def save(path: "/join", target: "Page:#{page.id}", record: shortcut, customer_id: customer.id, **params)
    described_class.call(shortcut: record, customer_id: customer_id, params: params.merge(path: path, target: target))
  end

  def enable_website
    enable_module!("website", customer, name: "Website")
  end

  it "returns the conventional success/model/field-errors API and ignores forged attributes" do
    Current.customer = other_customer
    result = save(path: "campaign/spring/", target_type: "Customer", target_id: other_customer.id, customer_id: customer.id)
    expect(result.success?).to be(true)
    expect(result.model).to equal(shortcut)
    expect(result.errors).to eq({})
    expect(shortcut.reload).to have_attributes(customer_id: customer.id, path: "/campaign/spring",
                                             target_type: "Page", target_id: page.id)
  end

  it "rejects unsupported/forged target selectors without constantizing them" do
    ["Customer:#{customer.id}", "Kernel:1", "Page:#{page.id}junk", "Page:0", "Page:#{page.id}:1", "Page:-1"].each do |target|
      result = save(target: target)
      expect(result.success?).to be(false)
      expect(result.errors[:target]).to include(I18n.t("page_shortcuts.errors.unavailable_target"))
    end
    expect(shortcut).not_to be_persisted
  end

  it "rejects private, cross-tenant and missing destinations but permits shared public Pages" do
    foreign = create(:page, customer: other_customer, launched: true, audience_member: true, audience_public: true)
    private_page = create(:page, :for_member, customer: customer, launched: true)
    [foreign.id, private_page.id, 999999999].each do |id|
      expect(save(target: "Page:#{id}").success?).to be(false)
    end
    shared = create(:page, :shared, launched: true, audience_member: true, audience_public: true)
    expect(save(target: "Page:#{shared.id}").success?).to be(true)
  end

  it "does not move an existing row across tenants, including a forged in-memory customer" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/join", target: page)
    result = save(record: record, customer_id: other_customer.id)
    expect(result.success?).to be(false)
    record.customer_id = other_customer.id
    expect(save(record: record, customer_id: other_customer.id).success?).to be(false)
    expect(record.reload.customer_id).to eq(customer.id)
    expect(save(customer_id: "#{customer.id}junk").success?).to be(false)
  end

  it "updates atomically and preserves the stored mapping when validation fails" do
    expect(save.success?).to be(true)
    original = shortcut.attributes.slice("path", "target_type", "target_id")
    result = save(path: "/admin", target: "Customer:1")
    expect(result.success?).to be(false)
    expect(result.errors.keys).to include(:path, :target)
    expect(shortcut.reload.attributes.slice("path", "target_type", "target_id")).to eq(original)
    expect(save(path: "/new-join").success?).to be(true)
    expect(shortcut.reload.path).to eq("/new-join")
  end

  it "applies explicit old values against the current persisted mapping after a concurrent edit" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/old-join", target: page)
    replacement = create(:page, customer: customer, launched: true, audience_member: true, audience_public: true)
    PageShortcut.find(record.id).update!(path: "/concurrent-join", target: replacement)

    result = save(record: record, path: "/old-join", target: "Page:#{page.id}")

    expect(result.success?).to be(true)
    expect(result.model).to equal(record)
    expect(record.reload).to have_attributes(path: "/old-join", target_type: "Page", target_id: page.id)
  end

  it "retains concurrently changed fields omitted from a stale update" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/old-join", target: page)
    replacement = create(:page, customer: customer, launched: true, audience_member: true, audience_public: true)
    PageShortcut.find(record.id).update!(path: "/concurrent-join", target: replacement)

    result = described_class.call(shortcut: record, customer_id: customer.id, params: { target: "Page:#{page.id}" })

    expect(result.success?).to be(true)
    expect(record.reload).to have_attributes(path: "/concurrent-join", target_id: page.id)
  end

  it "reloads persisted fields after acquiring the customer lock and before building the contract" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/old-join", target: page)
    replacement = create(:page, customer: customer, launched: true, audience_member: true, audience_public: true)
    allow(PageShortcuts::Collisions).to receive(:with_customer_lock).with(customer_id: customer.id).and_wrap_original do |original, **args, &write|
      original.call(**args) do
        PageShortcut.find(record.id).update!(path: "/concurrent-join", target: replacement)
        write.call
      end
    end

    result = described_class.call(shortcut: record, customer_id: customer.id, params: { path: "/old-join" })

    expect(result.success?).to be(true)
    expect(record.reload).to have_attributes(path: "/old-join", target_id: replacement.id)
  end

  it "leaves the latest persisted mapping intact when a stale submission fails" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/old-join", target: page)
    PageShortcut.find(record.id).update!(path: "/concurrent-join")

    result = save(record: record, path: "/admin", target: "Customer:1")

    expect(result.success?).to be(false)
    expect(result.errors.keys).to include(:path, :target)
    expect(record.reload).to have_attributes(path: "/concurrent-join", target_id: page.id)
  end

  it "returns localized invalid-customer results for missing, inactive and forged scopes" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/join", target: page)
    record.customer_id = other_customer.id
    I18n.with_locale(:"zh-CN") do
      [nil, "#{customer.id}junk", 99999999].each do |cid|
        result = save(customer_id: cid)
        expect(result.success?).to be(false)
        expect(result.errors[:base]).to include(I18n.t("page_shortcuts.errors.invalid_customer"))
      end
      result = save(record: record, customer_id: other_customer.id)
      expect(result.success?).to be(false)
      expect(result.errors[:base]).to include(I18n.t("page_shortcuts.errors.invalid_customer"))
      other_customer.update!(status: :inactive)
      result = save(customer_id: other_customer.id)
      expect(result.success?).to be(false)
      expect(result.errors[:base]).to include(I18n.t("page_shortcuts.errors.invalid_customer"))
    end
    expect(record.reload.customer_id).to eq(customer.id)
  end

  it "checks website collisions after entering the shared customer write boundary" do
    enable_website
    site = website
    page
    allow(PageShortcuts::Collisions).to receive(:with_customer_lock).with(customer_id: customer.id).and_wrap_original do |original, **args, &write|
      original.call(**args) do
        # A website writer won the path before this writer obtained the lock.
        create(:website_page, website: site, customer: customer, slug: "late-path", published: false)
        write.call
      end
    end

    result = save(path: "/late-path")

    expect(result.success?).to be(false)
    expect(result.errors[:path]).to include(I18n.t("page_shortcuts.errors.website_path_taken"))
    expect(shortcut).not_to be_persisted
  end

  it "rejects duplicate paths, allows identical paths across tenants and translates a unique-index race" do
    record = PageShortcut.create!(customer_id: customer.id, path: "/join", target: page)
    expect(save.errors[:path]).to include(I18n.t("page_shortcuts.errors.path_taken"))
    shared = create(:page, :shared, launched: true, audience_member: true, audience_public: true)
    expect(save(customer_id: other_customer.id, record: PageShortcut.new, target: "Page:#{shared.id}").success?).to be(true)
    allow(shortcut).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
    result = save(path: "/race")
    expect(result.success?).to be(false)
    expect(result.errors[:path]).to include(I18n.t("page_shortcuts.errors.path_taken"))
    expect(record.reload.path).to eq("/join")
  end

  it "reserves unpublished automatic inner slugs, but permits an explicit alias of the same page" do
    enable_website
    website_page.update!(published: false)
    expect(save(path: "/pricing").errors[:path]).to include(I18n.t("page_shortcuts.errors.website_path_taken"))
    website_page.update!(published: true)
    expect(save(path: "/pricing", target: "WebsitePage:#{website_page.id}").success?).to be(true)
  end

  it "allows root to explicitly map to a form Page even when an automatic website home exists" do
    enable_website
    create(:website_page, :published, :home, website: website)
    expect(save(path: "/").success?).to be(true)
  end

  it "allows home-page targets at arbitrary chosen nested paths" do
    enable_website
    home = create(:website_page, :published, :home, website: website)
    expect(save(path: "/campaign/welcome", target: "WebsitePage:#{home.id}").success?).to be(true)
  end
end
