# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Modules::Authentication::UserDomainSectionComponent, type: :component do
  let(:profile_class) { Authentication::UserDomainProfiles::Profile }
  let(:user) { build_stubbed(:user, :member, id: 42, customer_id: 12_345_678) }
  let(:domain) { EntityDomain.new(id: 7, customer_id: 12_345_678, name: "Education", description: "Academic records", color: "blue") }
  let(:profiles) do
    [
      profile_class.new(entity: Entity.new(id: 93, name: "Alumni", display_label: "Alumni", color: "teal"),
        entry: EntityEntry.new(id: 55, customer_id: 12_345_678, updated_at: Time.current), display: nil, groups: [],
        associations: [], form: nil),
      profile_class.new(entity: Entity.new(id: 94, name: "Student", display_label: "Student", color: "indigo"),
        entry: nil, display: nil, groups: [], associations: [], form: nil)
    ]
  end
  let(:section) { Authentication::UserDomainProfiles::Section.new(domain: domain, profiles: profiles) }

  def build_section(**options)
    described_class.new(section: section, user: user, customer_id: 12_345_678, id_prefix: "user-42", **options)
  end

  def render_section(**options)
    render_inline(build_section(**options))
  end

  it "renders the domain identity without a link ratio, and all cards in supplied order" do
    render_section

    expect(page).to have_css("section.card.overflow-hidden#user-42-domain-7[tabindex='-1'][aria-labelledby='user-42-domain-7-heading']")
    expect(page).to have_css("section > details.group\\/section[open] > summary h3", text: "Education")
    expect(page).to have_css("summary p", text: "Academic records")
    expect(page).to have_css("summary span.bg-blue-50.text-blue-700[aria-hidden='true'] path[d='#{EntitiesContributor::ICONS[:domain]}']")
    expect(page).not_to have_css("summary span.tabular-nums")
    expect(page).to have_css("section > details > div.divide-y.border-t > article", count: 2)
    expect(page.all("h4").map(&:text)).to eq(%w[Alumni Student])
    expect(page).to have_css("a[href='/12345678/admin/entities/93/entries/55']")
    expect(page).not_to have_css("a[href='/12345678/admin/entities/94']")
  end

  context "without a tenant domain" do
    let(:domain) { nil }

    it "renders the localized Other identity at call time without inventing a domain description" do
      I18n.with_locale(:"zh-CN") do
        render_section
        expect(page).to have_css("#user-42-domain-other h3", text: I18n.t("admin_misc.domains.directory.ungrouped"))
        expect(page).to have_css("summary span.bg-surface-active path[d='#{EntitiesContributor::ICONS[:ungrouped]}']")
        expect(described_class.dot_class(section)).to eq("bg-border-strong")
        expect(page).not_to have_text("Academic records")
      end
    end
  end

  it "collapses to its identity header when rendered closed" do
    render_section(open: false)

    expect(page).to have_css("section#user-42-domain-7 > details:not([open]) > summary h3", text: "Education")
    expect(page).not_to have_css("article")
    expect(page).to have_css("article", count: 2, visible: :all)
  end

  it "stays open when a profile's Create Entry form carries errors" do
    rejected = instance_double(Entities::EntryForm, errors: instance_double(ActiveModel::Errors, any?: true))
    clean = instance_double(Entities::EntryForm, errors: instance_double(ActiveModel::Errors, any?: false))

    closed_with = lambda do |form|
      described_class.new(section: section.with(profiles: [profiles.first, profiles.last.with(form: form)]),
                          user: user, customer_id: 12_345_678, id_prefix: "user-42", open: false)
    end

    expect(build_section(open: false).open?).to be(false)
    expect(closed_with.call(clean).open?).to be(false)
    expect(closed_with.call(rejected).open?).to be(true)
  end

  it "drops the entity-name row when the section's only profile is already linked, linking its entry from the header" do
    alone = profiles.first
    render_inline(described_class.new(section: section.with(profiles: [alone]), user: user,
                                      customer_id: 12_345_678, id_prefix: "user-42", open: false))

    heading = page.find("h4", visible: :all)
    expect(heading.text).to eq("Alumni")
    expect(heading[:class]).to eq("sr-only")
    expect(page).to have_css("h4.sr-only", count: 1, visible: :all)
    link = page.find("section#user-42-domain-7 > a[data-domain-entry-link='93']")
    expect(link[:href]).to eq("/12345678/admin/entities/93/entries/55")
    expect(link["aria-label"]).to eq(I18n.t("admin_modules.users.show.profiles.view_entry_label", entity: "Alumni", id: 55))
    expect(link).to have_text(I18n.t("admin_modules.users.show.profiles.view_entry"))
    expect(page).not_to have_css("summary a")
    expect(page.find("summary")[:class]).to include("pr-16", "sm:pr-36")
  end

  it "leaves the header without an entry link when the section holds several profiles or none is linked" do
    render_section
    expect(page).not_to have_css("section > a[data-domain-entry-link]")
    expect(page.find("summary")[:class]).not_to include("pr-16")

    render_inline(described_class.new(section: section.with(profiles: [profiles.last]), user: user,
                                      customer_id: 12_345_678, id_prefix: "user-42"))
    expect(page).not_to have_css("a[data-domain-entry-link]")
  end

  it "preserves a domain containing only missing profiles" do
    missing = profiles.map { |profile| profile.with(entry: nil) }
    section = self.section.with(profiles: missing)
    render_inline(described_class.new(section: section, user: user, customer_id: 12_345_678, id_prefix: "user-42"))

    expect(page).to have_css("article", count: 2)
    expect(page).not_to have_css("a")
  end

  it "escapes authored domain identity and description" do
    domain.name = "<script>domain()</script>"
    domain.description = "<img src=x onerror=domain()>"
    render_section

    expect(page).to have_css("h3", text: domain.name)
    expect(page).to have_text(domain.description)
    expect(page).not_to have_css("script, img")
  end
end
