# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageShortcuts::Hosts do
  let_it_be(:customer, refind: true) { create(:customer, id: 12345678) }
  let_it_be(:other_customer, refind: true) { create(:customer, id: 23456789) }

  after { Current.reset }

  it "normalizes case, trailing dots and IDNs through Addressable" do
    expect(described_class.normalize("Example.COM.")).to eq("example.com")
    expect(described_class.normalize("BÜCHER.Example.")).to eq("xn--bcher-kva.example")
    expect(described_class).not_to respond_to(:parse)
  end

  it "rejects invalid hosts and does not query mappings for nil or invalid input" do
    invalid = [nil, 1, "", "https://example.com", "example.com:443", "example.com:", "example.com/path",
               "*.example.com", "user@example.com", "example.com?x=1", "example.com#fragment",
               "bad_name.example", "example..com", "-bad.example", "example.com..", "exa%6dple.com"]
    expect(Customer).not_to receive(:domain_owner_id)
    invalid.each do |host|
      expect(described_class.normalize(host)).to be_nil
      expect(described_class.customer_id(host)).to eq(81721200)
      expect(described_class.dedicated?(host)).to be(false)
    end
  end

  it "uses exact stored bindings and the shared default, never subdomain inheritance" do
    create(:custom_domain, customer: customer, domain: "example.com")
    expect(described_class.customer_id("EXAMPLE.COM.")).to eq(customer.id)
    expect(described_class.customer_id("www.example.com")).to eq(81721200)
    expect(described_class.dedicated?("EXAMPLE.COM.")).to be(true)
    expect(described_class.customer_id("sub.example.com")).to eq(81721200)
    expect(described_class.dedicated?("sub.example.com")).to be(false)
    expect(described_class.customer_id).to eq(81721200)
    expect(described_class.path("/join", customer_id: customer.id)).to eq("/12345678/join")
    expect(described_class.path("/", customer_id: customer.id, host: "example.com")).to eq("/")
    expect(described_class.path("/", customer_id: 81721200, host: "example.com")).to eq("/81721200/")
  end

  it "keeps inactive bindings resolvable and dedicated, so the resolver fails closed instead of leaking the default" do
    create(:custom_domain, customer: customer, domain: "example.com")
    customer.soft_delete
    expect(described_class.customer_id("example.com")).to eq(customer.id)
    expect(described_class.dedicated?("example.com")).to be(true)
    ["/", "/join"].each do |path|
      request = ActionDispatch::Request.new(Rack::MockRequest.env_for("http://example.com#{path}"))
      expect(PageShortcuts::Resolver.resolve(request)).to be_nil
      expect(PageShortcuts::Resolver.unavailable_root?(request)).to be(true) if path == "/"
    end
    customer.restore
    expect(described_class.customer_id("example.com")).to eq(customer.id)
  end

  it "sees saves, renames, reassignment and deletion immediately even inside an AR query-cache scope" do
    customer.update!(domain: nil)
    other_customer.update!(domain: nil)
    allow(CustomDomains::CnameVerifier).to receive(:call).and_return(:verified)
    Customer.cache do
      expect(described_class.customer_id("example.com")).to eq(81721200)
      expect(customer.update(domain: "example.com")).to be(true)
      expect(described_class.customer_id("example.com")).to eq(customer.id)
      expect(described_class.dedicated?("example.com")).to be(true)
      customer.reload.update!(domain: nil)
      other_customer.reload.update!(domain: "renamed.com")
      expect(described_class.customer_id("example.com")).to eq(81721200)
      expect(described_class.dedicated?("example.com")).to be(false)
      expect(described_class.customer_id("renamed.com")).to eq(other_customer.id)
      other_customer.reload.update!(domain: nil)
      expect(described_class.customer_id("renamed.com")).to eq(81721200)
      expect(described_class.dedicated?("renamed.com")).to be(false)
    end
  end

  it "never rescues database failures into another tenant" do
    allow(Customer).to receive(:domain_owner_id).and_raise(ActiveRecord::StatementInvalid)
    expect { described_class.customer_id("example.com") }.to raise_error(ActiveRecord::StatementInvalid)
    expect { described_class.dedicated?("example.com") }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "captures a single dedicated host selection for bounded rendering and refreshes it in the next scope" do
    create(:custom_domain, customer: customer, domain: "example.com")
    shortcut = PageShortcut.new(customer_id: customer.id, path: "/join")
    count = 0
    callback = ->(_name, _start, _finish, _id, payload) { count += 1 if payload[:sql].match?(/SELECT\s.+"domain"/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      PageShortcuts::PublicPath.with_lookup(customer_id: customer.id, host: "example.com") do
        64.times { expect(PageShortcuts::PublicPath.shortcut(shortcut: shortcut, host: "EXAMPLE.COM.")).to eq("/join") }
        customer.update_columns(domain: nil)
        other_customer.update_columns(domain: "example.com")
        expect(PageShortcuts::PublicPath.shortcut(shortcut: shortcut, host: "example.com")).to eq("/join")
        expect(described_class.customer_id("example.com")).to eq(other_customer.id)
      end
    end
    # One presentation read and one live Hosts read; link count never introduces
    # additional hostname queries.
    expect(count).to eq(2)
    expect(Current.page_shortcuts_lookup).to be_nil
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id, host: "example.com") do
      expect(PageShortcuts::PublicPath.shortcut(shortcut: shortcut, host: "example.com")).to eq("/12345678/join")
      # A different host cannot borrow this scope's selection.
      expect(PageShortcuts::PublicPath.shortcut(shortcut: shortcut, host: "unmapped.example")).to eq("/12345678/join")
    end
  end

  it "keeps dedicated-host navigation SQL bounded as distinct destinations increase" do
    create(:custom_domain, customer: customer, domain: "example.com")
    render = ->(size) do
      count = 0
      callback = ->(_name, _start, _finish, _id, payload) do
        count += 1 unless payload[:name] == "SCHEMA" || payload[:sql].match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        PageShortcuts::PublicPath.with_lookup(customer_id: customer.id, host: "example.com") do
          2.times do
            size.times do |index|
              path = PageShortcuts::PublicPath.website_slug(slug: "destination-#{index}", customer_id: customer.id, host: "example.com")
              expect(path).to eq("/destination-#{index}")
            end
          end
        end
      end
      count
    end
    small = render.call(2)
    large = render.call(32)
    expect(large).to be <= small + 1
    expect(large).to be <= 7
  end

  it "restores the previous host snapshot across nested scopes and exceptions" do
    create(:custom_domain, customer: customer, domain: "example.com")
    PageShortcuts::PublicPath.with_lookup(customer_id: customer.id, host: "example.com") do
      outer = Current.page_shortcuts_lookup
      expect do
        PageShortcuts::PublicPath.with_lookup(customer_id: customer.id, host: "unmapped.example") do
          expect(Current.page_shortcuts_lookup.host).to eq("unmapped.example")
          raise "render failed"
        end
      end.to raise_error("render failed")
      expect(Current.page_shortcuts_lookup).to equal(outer)
    end
    expect(Current.page_shortcuts_lookup).to be_nil
  end

  it "does not access the table when drawing routes" do
    expect(Customer).not_to receive(:domain_owner_id)
    Rails.application.reload_routes!
  end
end
