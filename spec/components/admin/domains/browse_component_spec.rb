# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Domains::BrowseComponent, type: :component do
  let(:customer_id) { 12345678 }
  let(:academics) { build_stubbed(:entity_domain, id: 7, name: "Academics", color: "teal", description: "Courses and students") }

  def card(id, entry_count: 0, last_entry_at: nil, form_count: 0)
    Admin::Domains::Directory::Card.new(entity: instance_double(Entity, id: id), entry_count: entry_count,
                                        last_entry_at: last_entry_at, form_count: form_count)
  end

  def section(domain, *cards, unbound: 0)
    Admin::Domains::Directory::Section.new(domain: domain, cards: cards, unbound_form_count: unbound)
  end

  def render_browse(sections:, section:, &block)
    render_inline(described_class.new(sections: sections, section: section, customer_id: customer_id), &block)
  end

  def stats = page.all("dl[aria-label='Domain summary'] > div").map { |stat| [stat.find("dt").text.strip, stat.find("dd").text.strip] }

  it "heads a domain with its tinted icon, description and totals, and no tabs or body by default" do
    shown = section(academics, card(1, entry_count: 1200, last_entry_at: 2.hours.ago, form_count: 2), card(2, entry_count: 4))
    render_browse(sections: [shown, section(nil, card(3))], section: shown)

    expect(page).to have_css("h1", text: "Academics")
    expect(page).to have_css("p", text: "Courses and students")
    expect(page).to have_css("span.bg-teal-50.text-teal-700 path[d='#{EntitiesContributor::ICONS[:domain]}']")
    expect(page).to have_css("nav a[href='/#{customer_id}/admin/domains']", text: "Domains")
    expect(stats).to eq([["Record types", "2"], ["Total entries", "1,204"], ["Pages", "2"], ["Last activity", "about 2 hours ago"]])
    expect(page).to have_css("[data-role='stat-entries'].rounded-2xl.border dd.text-3xl")
    expect(page).to have_css("[data-role='stat-entries'] path[d='#{described_class::STAT_ICONS[:entries]}']")
    expect(page).to have_css("[data-role='stat-activity'] dd time[datetime][title]", text: "about 2 hours ago")
    expect(page).not_to have_css("[data-section-nav-tab]")
    expect(page).not_to have_css("div.mt-6")
    expect(page.text).not_to match(/entit/i)
  end

  it "renders a given body below the totals" do
    shown = section(academics, card(1))
    render_browse(sections: [shown], section: shown) { "BODY" }

    expect(page).to have_css("div.mt-6", text: "BODY")
  end

  it "heads the ungrouped section as Other, its idle activity muted" do
    other = section(nil, unbound: 3)
    render_browse(sections: [section(academics, card(1)), other], section: other)

    expect(page).to have_css("h1", text: "Other")
    expect(page).to have_css("p", text: "Not assigned to a domain yet.")
    expect(page).to have_css("span.bg-surface-active path[d='#{EntitiesContributor::ICONS[:ungrouped]}']")
    expect(stats).to eq([["Record types", "0"], ["Total entries", "0"], ["Pages", "3"], ["Last activity", "No activity yet"]])
    expect(page).to have_css("[data-role='stat-activity'] dd.text-text-muted", text: "No activity yet")
    expect(page).not_to have_css("[data-role='stat-activity'] time")
  end

  it "keeps the generic Domains header, without an icon or breadcrumb link, while the customer has no domains" do
    only = section(nil, card(1))
    render_browse(sections: [only], section: only)

    expect(page).to have_css("h1", text: "Domains")
    expect(page).to have_css("p", text: "Browse your organization's records, grouped by business area.")
    expect(page).not_to have_css("h1 ~ svg, span.rounded-xl svg")
    expect(page).not_to have_css("nav a[href='/#{customer_id}/admin/domains']")
    expect(stats.map(&:first)).to eq(["Record types", "Total entries", "Pages", "Last activity"])
  end

  it "shows an empty state instead of totals when there is nothing to browse" do
    render_browse(sections: [], section: nil)

    expect(page).to have_css("h1", text: "Domains")
    expect(page).to have_text("Nothing to browse yet")
    expect(page).not_to have_css("dl")
    expect(page.text).not_to match(/entit/i)
  end
end
