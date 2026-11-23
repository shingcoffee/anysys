# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::SectionIndexComponent, type: :component do
  let(:items) do
    [
      { id: "user-42-domain-7", label: "Education #{'long domain ' * 12}", dot: "bg-blue-500" },
      { id: "user-42-devices", label: I18n.t("admin_modules.users.show.trusted_devices"), dot: "bg-violet-500", count: 3 },
      { id: "user-42-sign-ins", label: I18n.t("admin_modules.users.show.sign_in_activity") }
    ]
  end

  it "renders plain anchor links when no link action is given" do
    render_inline(described_class.new(items: items, id_prefix: "entry"))

    expect(page).to have_css("nav[aria-labelledby='entry-sections-heading'] a[href='#user-42-domain-7']")
    expect(page).not_to have_css("a[data-action]")
  end

  it "renders a labelled desktop-only jump list in supplied order with dots and counts" do
    render_inline(described_class.new(items: items, id_prefix: "user-42", link_action: "section-reveal#open"))

    nav = page.find("nav[aria-labelledby='user-42-sections-heading']")
    expect(nav[:class]).to include("hidden", "lg:block", "card")
    expect(page).to have_css("nav > h2#user-42-sections-heading", text: I18n.t("admin_misc.entities.entry_detail.sections_heading"))
    expect(page).not_to have_css("nav svg")
    expect(page.all("nav a").map { |node| node[:href] }).to eq(%w[#user-42-domain-7 #user-42-devices #user-42-sign-ins])
    expect(page).to have_css("span.truncate[title='#{items.first[:label]}']", text: items.first[:label])
    expect(page).to have_css("span.bg-blue-500[aria-hidden='true']")
    expect(page).to have_css("span.bg-border-strong[aria-hidden='true']")
    expect(page.all("nav a").map { |node| node[:class] }).to all(include("focus-visible:outline-accent"))
    expect(page).not_to have_css("[data-controller]")
    expect(page.all("nav a").map { |node| node["data-action"] }).to all(eq("section-reveal#open"))
  end

  it "shows a count only on items that supply one" do
    rendered = render_inline(described_class.new(items: items, id_prefix: "user-42"))

    domain, devices, sign_ins = rendered.css("nav a")
    expect(domain.at_css(".tabular-nums")).to be_nil
    expect(devices.at_css(".tabular-nums").text).to eq("3")
    expect(sign_ins.at_css(".tabular-nums")).to be_nil
  end

  it "keeps authored labels and counts escaped" do
    render_inline(described_class.new(items: [{ id: "user-42-domain-7", label: "<script>domain()</script>", count: "<b>1</b>" }], id_prefix: "user-42"))

    expect(page).to have_text("<script>domain()</script>")
    expect(page).to have_text("<b>1</b>")
    expect(page).not_to have_css("script, b")
  end
end
