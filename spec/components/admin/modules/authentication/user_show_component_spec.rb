# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Modules::Authentication::UserShowComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81_721_200) }
  let(:viewer) { build_stubbed(:user, :admin, customer: customer, first_name: "Ada", last_name: "Admin") }
  let(:user) do
    build_stubbed(
      :user,
      :member,
      id: 42,
      customer: customer,
      first_name: "Lin",
      last_name: "Member",
      email: "lin@example.com",
      status: "active"
    )
  end

  let(:section_class) { Authentication::UserDomainProfiles::Section }
  let(:profile_class) { Authentication::UserDomainProfiles::Profile }
  let(:profile_sections) do
    [
      section_class.new(
        domain: EntityDomain.new(id: 10, customer_id: customer.id, name: "Education", description: "Academic records", color: "blue"),
        profiles: [profile(93, "Alumni", entry_id: 55), profile(94, "Student")]
      ),
      section_class.new(
        domain: EntityDomain.new(id: 11, customer_id: customer.id, name: "Volunteering", color: "teal"),
        profiles: [profile(95, "Volunteer")]
      ),
      section_class.new(domain: nil, profiles: [profile(96, "Contact", entry_id: 56)])
    ]
  end

  def profile(id, label, entry_id: nil)
    entity = Entity.new(id: id, name: label, display_label: label, icon: "user", color: "indigo")
    entry = EntityEntry.new(id: entry_id, customer_id: customer.id, updated_at: Time.zone.parse("2026-11-01 12:00")) if entry_id
    profile_class.new(entity: entity, entry: entry, display: nil, groups: [], associations: [], form: nil)
  end

  def render_show(target: user, devices: [], sections: [], actor: viewer, cid: customer.id)
    with_request_url("/#{customer.id}/admin/modules/authentication/users/#{target.id}") do
      render_inline(described_class.new(user: target, trusted_devices: devices, viewer: actor,
                                       customer_id: cid, profile_sections: sections))
    end
  end

  it "renders identity, role, and edit without activating the viewer" do
    render_show

    expect(page).to have_css("h1", text: user.display_name)
    expect(page).to have_text(user.email)
    expect(page).to have_text(I18n.t("admin_modules.users.show.details"))
    expect(page).to have_link(I18n.t("common.actions.edit"))
    expect(page).to have_text(I18n.t("admin_modules.users.actions.deactivate"))
    expect(page).to have_link(I18n.t("admin_modules.nav.modules"), href: "/#{customer.id}/admin/modules")
  end

  it "omits activate/deactivate when viewing yourself" do
    render_show(target: viewer)

    expect(page).to have_css("h1", text: viewer.full_name)
    expect(page).not_to have_text(I18n.t("admin_modules.users.actions.deactivate"))
    expect(page).not_to have_text(I18n.t("admin_modules.users.actions.activate"))
    expect(page).not_to have_text(I18n.t("admin_modules.users.actions.move_to_trash"))
  end

  it "uses the email fallback for the heading and final breadcrumb, wrapping long identity text and actions" do
    user.first_name = nil
    user.last_name = nil
    user.email = "#{'long' * 40}@example.com"
    render_show

    expect(page).to have_css("h1", text: user.email)
    expect(page.find("h1")[:class]).to include("break-words", "[overflow-wrap:anywhere]")
    expect(page.find("h1")[:class]).not_to include("truncate")
    expect(page).to have_css("nav[aria-label] span", text: user.email)
    expect(page).to have_css("p > span.break-words", text: user.email)
    edit = page.find("a.btn-primary", text: I18n.t("common.actions.edit"))
    expect(edit[:class]).to include("min-h-11", "flex-1", "sm:min-h-9", "sm:flex-none")
    expect(edit.find(:xpath, "..")[:class]).to include("flex-wrap", "sm:flex-nowrap")
    expect(page).to have_css("h1 + .badge-success", text: I18n.t("common.status.active"))
  end

  it "keeps compact account metadata first on mobile and the section index in the desktop sidebar only" do
    render_show(sections: profile_sections)

    aside = page.find("aside")
    expect(aside[:class]).to include("lg:col-start-2", "lg:sticky", "lg:max-h-[calc(100dvh-3rem)]", "lg:overflow-y-auto", "gap-6")
    expect(aside.find(:xpath, "..").all(:xpath, "./*").first.tag_name).to eq("aside")
    details = aside.find("#user-42-details")
    expect(details).to have_css("dd", text: "#42")
    expect(details).to have_text(user.role_display_name)
    expect(details).to have_css("time[datetime='#{user.created_at.iso8601}']")
    expect(details).to have_css("time[datetime='#{user.updated_at.iso8601}']")
    expect(aside).to have_css("nav.hidden.lg\\:block", count: 1)
  end

  it "uses a role-tinted person tile as the page identity instead of the module icon" do
    render_show
    expect(page).to have_css("h1", text: user.display_name)
    tile = page.find("span.size-10[aria-hidden='true']")
    expect(tile[:class]).to include("bg-slate-100", "text-slate-600", "ring-1")
    expect(tile).to have_css("path[d='#{EntityAttributeGroupingHelper::ICON_PATHS.fetch('user')}']")

    allow(user).to receive(:primary_role_key).and_return("admin")
    render_show
    expect(page.find("span.size-10[aria-hidden='true']")[:class]).to include("bg-indigo-50", "text-indigo-600")
  end

  it "renders each domain as its own card with a tinted tile, then the security cards" do
    render_show(sections: profile_sections)

    %w[user-42-domain-10 user-42-domain-11 user-42-domain-other user-42-details].each do |id|
      expect(page.find("##{id}")[:class]).to include("card", "overflow-hidden")
    end
    expect(page.find("#user-42-domain-10 summary")).to have_css("span.bg-blue-50.text-blue-700")
    expect(page.find("#user-42-domain-11 summary")).to have_css("span.bg-teal-50.text-teal-700")
    expect(page.find("#user-42-domain-other summary")).to have_css("span.bg-surface-active")
    expect(page).to have_css("#user-42-profiles-heading.sr-only", text: I18n.t("admin_modules.users.show.profiles.heading"))
    aside = page.find("aside")
    summary = aside.find("#user-42-sign-ins > details:not([open]) summary")
    expect(summary).to have_css("h3", text: I18n.t("admin_modules.users.show.sign_in_and_devices"))
    expect(summary).to have_text(I18n.t("admin_modules.users.show.trusted_devices_count", count: 0))
    expect(page.find("#user-42-profiles").find(:xpath, "..")).not_to have_css("#user-42-sign-ins, #user-42-devices", visible: :all)
  end

  it "merges account details, sign-in activity and trusted devices into one card" do
    render_show

    card = page.find("#user-42-details")
    expect(page).to have_css("section.card", count: 1)
    expect(card).to have_css("> h2#user-42-details-heading", text: I18n.t("admin_modules.users.show.details"))
    expect(card).to have_css("> dl + #user-42-sign-ins.border-t[role='group'] > details:not([open])")
    folded = card.find("#user-42-sign-ins")
    expect(folded.all("h4", visible: :all).map { |node| node.text(:all) }).to eq([
      I18n.t("admin_modules.users.show.sign_in_activity"), I18n.t("admin_modules.users.show.trusted_devices")
    ])
    expect(folded).to have_css("details > [role='group'][aria-labelledby='user-42-activity-heading'] dl", visible: :all)
    expect(folded).to have_css("details > #user-42-devices[role='group'][aria-labelledby='user-42-devices-heading']", visible: :all)
  end

  it "collapses every domain card when there are several, and wires the index to reveal them" do
    render_show(sections: profile_sections)

    expect(page).to have_css("#user-42-profiles > section > details:not([open])", count: 3)
    expect(page).not_to have_css("#user-42-profiles article")
    expect(page.find("aside").find(:xpath, "..")["data-controller"]).to eq("section-reveal")
    expect(page.all("aside nav a").map { |node| node["data-action"] }).to all(eq("section-reveal#open"))
  end

  it "expands a lone domain card" do
    render_show(sections: profile_sections.first(1))

    expect(page).to have_css("#user-42-domain-10 > details[open]")
    expect(page).to have_css("#user-42-domain-10 article", count: 2)
  end

  it "renders domains, every profile type, Other, then security cards in projection order" do
    render_show(sections: profile_sections)

    expect(page.all("#user-42-profiles h3").map(&:text)).to eq(["Education", "Volunteering", I18n.t("admin_misc.domains.directory.ungrouped")])
    expect(page.all("#user-42-profiles h4", visible: :all).map { |node| node.text(:all) }).to eq(%w[Alumni Student Volunteer Contact])
    expect(page).not_to have_text(/\d+\/\d+ linked/)
    main = page.find("#user-42-profiles").find(:xpath, "..")
    expect(main.all(:xpath, "./section").map { |node| node[:id] }).to eq(%w[user-42-profiles])
    expect(page.find("aside").all("section").map { |node| node[:id] }).to eq(%w[user-42-details])
    expect(page).not_to have_text(I18n.t("admin_modules.users.show.profiles.no_types"))
  end

  it "has one ordered index whose links resolve to unique, focusable section targets" do
    rendered = render_show(sections: profile_sections)

    expect(rendered.css("[id]").map { |node| node["id"] }).to eq(rendered.css("[id]").map { |node| node["id"] }.uniq)
    links = rendered.css("aside nav a")
    expect(links.map { |node| node["href"] }).to eq(%w[#user-42-domain-10 #user-42-domain-11 #user-42-domain-other #user-42-sign-ins])
    links.each do |link|
      targets = rendered.css(link["href"])
      expect(targets.size).to eq(1)
      expect(targets.first["tabindex"]).to eq("-1")
      expect(targets.first["class"]).to include("scroll-mt-6", "focus-visible:outline-accent")
      expect(link["class"]).to include("focus-visible:outline-accent")
    end
    rendered.css("[aria-labelledby]").each do |node|
      expect(rendered.css("##{node['aria-labelledby']}").size).to eq(1)
    end
    expect(links[0].text.squish).to eq("Education")
    expect(links[0].at_css(".tabular-nums")).to be_nil
    expect(links[0].at_css("span.bg-blue-500")).to be_present
    expect(links[3].at_css("span.bg-sky-500")).to be_present
    expect(links[3].text.squish).to eq("#{I18n.t('admin_modules.users.show.sign_in_and_devices')} 0")
  end

  it "explains the absence of eligible types while retaining account, sign-ins, devices and a Profiles index target" do
    render_show

    expect(page).to have_text(I18n.t("admin_modules.users.show.profiles.no_types"))
    expect(page.find("#user-42-profiles")).not_to have_css("h3, article")
    expect(page).to have_css("#user-42-details")
    expect(page).to have_css("#user-42-sign-ins > details:not([open]) #user-42-devices", visible: :all)
    expect(page.find("#user-42-devices", visible: :all)).to have_text(:all, I18n.t("admin_modules.users.show.trusted_devices_empty"))
    expect(page).to have_link(I18n.t("admin_modules.users.show.profiles.heading"), href: "#user-42-profiles")
  end

  it "offers Reset MFA when the user has configured MFA" do
    target = build_stubbed(
      :user, :member, :mfa_configured,
      id: 43, customer: customer, first_name: "Mia", last_name: "Mfa"
    )
    render_show(target: target)

    reset = page.find("a", text: I18n.t("admin_modules.users.actions.reset_mfa"))
    expect(reset[:href]).to eq("/#{customer.id}/admin/modules/authentication/users/43/mfa_reset")
    expect(reset["data-turbo-method"]).to eq("post")
    expect(reset["data-turbo-confirm"]).to eq(I18n.t("admin_modules.users.show.reset_mfa_confirm", name: target.display_name))
    expect(page.find("#user-43-details")).to have_css(".badge-warning", text: I18n.t("admin_modules.users.show.mfa_configured"))
  end

  it "omits self admin MFA reset even when configured" do
    allow(viewer).to receive(:mfa_configured?).and_return(true)
    render_show(target: viewer)

    expect(page).not_to have_link(I18n.t("admin_modules.users.actions.reset_mfa"))
    expect(page).to have_link(I18n.t("common.actions.edit"))
  end

  it "prioritizes enforced MFA over configured and retains the unconfigured state" do
    target = build_stubbed(:user, :member, :with_mfa, id: 43, customer: customer)
    render_show(target: target)
    expect(page.find("#user-43-details")).to have_css(".badge-success", text: I18n.t("common.status.enabled"))
    expect(page).not_to have_text(I18n.t("admin_modules.users.show.mfa_configured"))

    render_show
    expect(page.find("#user-42-details")).to have_css(".badge-default", text: I18n.t("admin_modules.users.show.mfa_not_set_up"))
  end

  it "omits protected owner mutations for a non-owner viewer" do
    allow(user).to receive_messages(owner?: true, primary_role_key: "owner", mfa_configured?: true)
    render_show

    expect(page).not_to have_css("a.btn")
    expect(page.find("#user-42-details")).to have_css(".bg-purple-100")
    expect(page).to have_css("h1", text: user.display_name)
  end

  it "retains permitted mutations and tenant links when an owner views a different tenant" do
    allow(viewer).to receive(:owner?).and_return(true)
    allow(user).to receive(:mfa_configured?).and_return(true)
    render_show(sections: profile_sections, cid: 12_345_678)

    expect(page).to have_link(I18n.t("common.actions.edit"), href: "/12345678/admin/modules/authentication/users/42/edit")
    expect(page).to have_css("a[href='/12345678/admin/modules/authentication/users/42/mfa_reset']")
    expect(page).to have_css("a[href='/12345678/admin/modules/authentication/users/42/activation']")
    expect(page).to have_css("a[href='/12345678/admin/entities/93/entries/55']", visible: :all)
    expect(page).not_to have_css("a[href='/12345678/admin/entities/94']", visible: :all)
  end

  it "retains the destructive lifecycle confirmation as the last header action" do
    allow(user).to receive(:mfa_configured?).and_return(true)
    render_show

    actions = page.all("a.btn")
    expect(actions.map { |node| node.text.squish }).to eq([
      I18n.t("common.actions.edit"),
      I18n.t("admin_modules.users.actions.reset_mfa"),
      I18n.t("admin_modules.users.actions.deactivate"),
      I18n.t("admin_modules.users.actions.move_to_trash")
    ])
    trash = actions.last
    expect(trash["href"]).to eq("/#{customer.id}/admin/modules/authentication/users/#{user.id}")
    expect(trash["data-turbo-method"]).to eq("delete")
    expect(trash["data-turbo-confirm"]).to eq(I18n.t("admin_modules.users.show.trash_confirm", name: user.display_name))
    expect(page.all("a.btn-primary").map { |node| node.text.squish }).to eq([I18n.t("common.actions.edit")])
    [trash, actions[2]].each do |destructive|
      expect(destructive[:class]).to include("btn-secondary", "text-danger")
      expect(destructive[:class]).not_to include("btn-danger")
    end
  end

  it "offers Activate for an inactive user who is not the viewer" do
    target = build_stubbed(
      :user, :member, :inactive,
      id: 44, customer: customer, first_name: "Ian", last_name: "Inactive"
    )
    render_show(target: target)

    expect(page).to have_text(I18n.t("admin_modules.users.actions.activate"))
    expect(page).not_to have_text(I18n.t("admin_modules.users.actions.deactivate"))
    expect(page).to have_css("a.btn-secondary[data-turbo-method='post']", text: I18n.t("admin_modules.users.actions.activate"))
    expect(page).to have_css("h1 + .badge-danger", text: I18n.t("common.status.inactive"))
  end

  it "retains sign-in counts, times, IPv6 addresses, failures and the lock annotation" do
    time = Time.zone.parse("2026-11-01 12:00")
    user.assign_attributes(sign_in_count: 7, last_sign_in_at: time, current_sign_in_at: time + 1.hour,
                           last_sign_in_ip: "2001:db8:85a3:0000:0000:8a2e:0370:7334", current_sign_in_ip: "192.0.2.8",
                           failed_attempts: 3, locked_at: time + 2.hours)
    render_show

    card = page.find("#user-42-sign-ins")
    expect(card).to have_css("dd", text: "7", exact_text: true, visible: :all)
    expect(card).to have_css("dd", text: "3", visible: :all)
    expect(card).to have_css("dd.font-mono", text: user.last_sign_in_ip, visible: :all)
    expect(card).to have_css("dd.font-mono", text: user.current_sign_in_ip, visible: :all)
    expect(card).to have_css("time[datetime='#{time.iso8601}']", visible: :all)
    expect(card).to have_css("time[datetime='#{(time + 1.hour).iso8601}']", visible: :all)
    expect(card).to have_text(:all, I18n.t("admin_modules.users.show.locked_at", time: I18n.l(user.locked_at, format: :long)))
  end

  it "keeps the sidebar cards in the entry page's plain style: text headings and label/value rows, no icon tiles" do
    render_show

    aside = page.find("aside")
    expect(aside).not_to have_css("span.size-8")
    details = aside.find("#user-42-details")
    expect(details).to have_css("h2#user-42-details-heading.text-sm.border-b", text: I18n.t("admin_modules.users.show.details"))
    expect(details.all("dl > div > dt").map(&:text)).to eq([
      I18n.t("admin_misc.entities.columns.id"), I18n.t("admin_modules.users.show.role"), I18n.t("common.labels.status"),
      I18n.t("admin_modules.users.show.mfa"), I18n.t("common.labels.created_at"), I18n.t("common.labels.updated_at")
    ])
    expect(details.all("dd .badge").map { |node| node.text.strip }).to eq([user.role_display_name, I18n.t("common.status.active"),
                                                                          I18n.t("admin_modules.users.show.mfa_not_set_up")])
    expect(aside).to have_css("#user-42-details > #user-42-sign-ins > details:not([open]) > summary > h3#user-42-sign-ins-heading.text-sm")
  end

  it "uses muted localized blanks for never-signed-in accounts" do
    render_show

    expect(page.find("#user-42-sign-ins")).to have_css(".text-text-tertiary", text: I18n.t("common.labels.em_dash"), count: 4, visible: :all)
    expect(page.all("#user-42-sign-ins dd", visible: :all).count { |node| node.text.strip == "0" }).to eq(2)
  end

  it "shows complete wrapping device metadata and preserves each tenant-scoped revoke form and confirmation" do
    time = Time.zone.parse("2026-11-01 12:00")
    device = ::Authentication::TrustedDevice.new(id: 71, user_id: user.id, customer_id: customer.id,
      user_agent: "Mozilla/5.0 #{'long-agent-' * 35}", ip: "2001:db8::8", last_used_at: time, expires_at: time + 30.days)
    unknown = ::Authentication::TrustedDevice.new(id: 72, user_id: user.id, customer_id: customer.id,
      user_agent: "", ip: nil, last_used_at: nil, expires_at: time + 60.days)
    render_show(devices: [device, unknown], cid: 12_345_678)

    card = page.find("#user-42-devices", visible: :all)
    expect(card).to have_text(:all, device.user_agent)
    expect(card).not_to have_css(".truncate", visible: :all)
    expect(card).to have_text(:all, I18n.t("admin_modules.users.show.device_unknown"))
    expect(card).to have_text(:all, I18n.t("admin_modules.users.show.device_last_used", time: I18n.t("common.labels.em_dash")))
    expect(card).to have_css("time[datetime='#{time.iso8601}']", visible: :all)
    expect(card).to have_css("time[datetime='#{device.expires_at.to_date.iso8601}']", visible: :all)
    [71, 72].each do |id|
      form = card.find("form[action='/12345678/admin/modules/authentication/users/42/trusted_devices/#{id}']", visible: :all)
      expect(form).to have_css("input[name='_method'][value='delete']", visible: :all)
      expect(form).to have_button(I18n.t("admin_modules.users.show.trusted_device_revoke"), visible: :all)
      expect(form.find("button", visible: :all)["data-turbo-confirm"]).to eq(I18n.t("admin_modules.users.show.trusted_device_revoke_confirm"))
    end
  end

  it "renders profile states, metadata and actions in both supported locales with stable IDs" do
    %i[en zh-CN].each do |locale|
      I18n.with_locale(locale) do
        render_show(sections: profile_sections)
        expect(page).to have_css("#user-42-profiles-heading", text: I18n.t("admin_modules.users.show.profiles.heading"))
        expect(page).to have_css("#user-42-domain-other-heading", text: I18n.t("admin_misc.domains.directory.ungrouped"))
        expect(page).to have_text(:all, I18n.t("admin_modules.users.show.profiles.missing_description", entity: "Student"))
        expect(page).to have_text(I18n.t("admin_modules.users.show.trusted_devices_count", count: 0))
        expect(page).to have_text(:all, I18n.t("admin_modules.users.show.profiles.no_fields"))
        expect(page).to have_css("a[aria-label='#{I18n.t("admin_modules.users.show.profiles.view_entry_label", entity: "Alumni", id: 55)}']", text: I18n.t("admin_modules.users.show.profiles.view_entry"), visible: :all)
        expect(page).to have_link(I18n.t("common.actions.edit"))
        expect(page).not_to have_css(".translation_missing")
      end
    end
  end

  it "mounts the association dialog only when a linked profile offers Add on an association" do
    render_show(sections: profile_sections)
    expect(page).not_to have_css("dialog#entity-quick-add-dialog-0", visible: :all)

    offers_add = ->(writable, associations) { profile_sections.first.profiles.first.with(associations_writable: writable, associations: associations) }
    build = ->(profile) { described_class.new(user: user, trusted_devices: [], viewer: viewer, customer_id: customer.id,
                                               profile_sections: [section_class.new(domain: nil, profiles: [profile])]) }
    expect(build.call(offers_add.call(true, [:section])).association_dialog?).to be(true)
    expect(build.call(offers_add.call(false, [:section])).association_dialog?).to be(false)
    expect(build.call(offers_add.call(true, [])).association_dialog?).to be(false)
  end

  it "keeps the new locale keys and interpolation variables in parity" do
    translations = %w[en zh-CN].map do |locale|
      YAML.load_file(Rails.root.join("config/locales/admin_modules.#{locale}.yml")).dig(locale, "admin_modules", "users", "show", "profiles")
    end
    expect(translations[0].keys.sort).to eq(translations[1].keys.sort)
    translations[0].each do |key, value|
      expect(value.scan(/%\{([^}]+)\}/).flatten.sort).to eq(translations[1].fetch(key).scan(/%\{([^}]+)\}/).flatten.sort)
    end
  end
end
