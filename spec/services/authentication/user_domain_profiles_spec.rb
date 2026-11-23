# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authentication::UserDomainProfiles do
  let_it_be(:customer) { create(:customer) }
  let_it_be(:viewer) { create(:user, :admin, customer: customer) }
  let_it_be(:user) { create(:user, :member, customer: customer) }
  let(:owner) { find_or_create_platform_owner }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }

  before do
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
  end

  def person(name, **attributes)
    create(:entity, customer: customer, name: name, extended_model: person_model, **attributes)
  end

  def shared_person(name, **attributes)
    # Shared extension identity is not exposed by the current definition writer.
    # Keep its real global version line, then stamp that identity for the reader.
    create(:entity, :shared, name: name, **attributes).tap do |entity|
      entity.update_columns(extended_model: person_model, category: Entity.categories.fetch("extension"))
    end
  end

  def place(entity, domain, tenant: customer)
    EntityDomainMembership.create!(customer: tenant, entity_domain: domain, entity: entity)
  end

  def link(entity, data: {}, account: user, tenant: customer)
    create(:entity_entry, customer: tenant, entity: entity, user: account, data: data.to_json)
  end

  def project(account: user, tenant: customer, actor: viewer)
    described_class.call(user: account, customer: tenant, viewer: actor)
  end

  def profiles(sections)
    sections.flat_map(&:profiles)
  end

  it "returns no sections when no eligible person definitions exist" do
    domain = create(:entity_domain, customer: customer)
    place(create(:entity, customer: customer), domain)

    expect(project).to eq([])
  end

  it "orders represented domains, retains missing types, and puts Other last" do
    commerce = create(:entity_domain, customer: customer, name: "Commerce")
    academics = create(:entity_domain, customer: customer, name: "academics")
    irrelevant = create(:entity_domain, customer: customer, name: "Irrelevant")
    create(:entity_domain, customer: customer, name: "Empty")
    place(create(:entity, customer: customer), irrelevant)

    zulu = person("Zulu")
    alpha = person("First alpha", display_label: "alpha")
    alpha_tie = person("Second alpha", display_label: "ALPHA")
    student = person("Student")
    other = person("Ungrouped")
    [zulu, alpha_tie, alpha].each { |entity| place(entity, commerce) }
    place(student, academics)
    entry = link(alpha)

    sections = project

    expect(sections.map(&:domain)).to eq([academics, commerce, nil])
    expect(sections.map { |section| section.profiles.count(&:entry) }).to eq([0, 1, 0])
    expect(sections.map { |section| section.profiles.map(&:entity) }).to eq([[student], [alpha, alpha_tie, zulu], [other]])
    expect(sections).to all(be_a(described_class::Section))
    expect(sections.first.members).to eq(%i[domain profiles])
    linked = sections[1].profiles.first
    expect(linked).to be_a(described_class::Profile)
    expect(linked.members).to eq(%i[entity entry display groups associations form associations_writable])
    expect(linked.entry).to eq(entry)
    expect(linked.display).to be_a(Entities::EntryDisplay)
    expect(linked.associations).to eq([])
    expect(linked.form).to be_nil
    missing = sections[1].profiles.last
    expect(missing.entry).to be_nil
    expect(missing.display).to be_nil
    expect(missing.groups).to eq([])
    expect(missing.associations).to eq([])
    expect(missing.form).to be_a(Entities::EntryForm)
    expect(missing.associations_writable).to be(false)
  end

  it "gives a missing profile the entity's create form, a supplied replacement, or none for an inactive account" do
    entity = person("Student", property_schema: [{ name: "Major", name_slug: "major", html_type: "text" }].to_json)

    form = profiles(project).sole.form
    expect(form.entity).to eq(entity)
    expect(form.customer).to eq(customer)
    expect(form.errors).to be_empty

    replacement = Entities::EntryForm.new(entity: entity, customer: customer, params: { "major" => "Art" })
    supplied = described_class.call(user: user, customer: customer, viewer: viewer, forms: { entity.id => replacement })
    expect(profiles(supplied).sole.form).to equal(replacement)

    inactive = create(:user, :member, :inactive, customer: customer)
    expect(profiles(project(account: inactive)).sole.form).to be_nil
  end

  context "with an association on the profile entity" do
    include_context "student course association"

    let(:student_entity) do
      person("Student", display_label: "Student",
                        property_schema: [{ "name" => "Full Name", "name_slug" => "full_name", "html_type" => "text" }].to_json)
    end

    it "carries a linked entry's association rows with their display text" do
      student.update_column(:user_id, user.id)
      enroll(student, math, status: "enrolled", grade: "90")

      profile = profiles(project).sole
      section = profile.associations.sole
      expect(profile.entry).to eq(student)
      expect(section.association.target).to eq(course_entity)
      expect(section.display.text(section.rows.sole, "course")).to eq("MATH-101")
      expect(section.display.text(section.rows.sole, "grade")).to eq("90")
      expect(section.existing_target_ids).to eq("course" => Set[math.id.to_s])
      expect(profile.associations_writable).to be(true)
    end

    it "withholds association Add from a viewer who may not create association rows" do
      student.update_column(:user_id, user.id)
      ability = Ability.new(viewer)
      ability.cannot :create, :route_admin_entity_association_entries
      allow(Ability).to receive(:new).with(viewer).and_return(ability)

      profile = profiles(project).sole
      expect(profile.associations.size).to eq(1)
      expect(profile.associations_writable).to be(false)
    end
  end

  it "keeps multiple explicitly linked profile types in the same domain" do
    domain = create(:entity_domain, customer: customer)
    student = person("Student")
    volunteer = person("Volunteer")
    missing = person("Patient")
    [student, volunteer, missing].each { |entity| place(entity, domain) }
    student_entry = link(student)
    volunteer_entry = link(volunteer)

    section = project.fetch(0)

    expect(section.profiles.map(&:entity)).to eq([missing, student, volunteer])
    expect(section.profiles.map(&:entry)).to eq([nil, student_entry, volunteer_entry])
  end

  it "uses Unicode case-folded labels and the entity id to break ties" do
    first = person("First", display_label: "straße")
    second = person("Second", display_label: "STRASSE")
    earlier = person("Earlier", display_label: "aardvark")

    expect(profiles(project).map(&:entity)).to eq([earlier, first, second])
  end

  it "includes a person type that is an association child rather than a navigation root" do
    child = person("Student", property_schema: [{ name: "Name", name_slug: "name", html_type: "text" }].to_json)
    create(:entity, customer: customer, name: "Classroom", associations: [
      { target_entity_id: child.id.to_s, target_entity_name: child.name, display_field: "name", display_field_label: "Name" }
    ].to_json)
    entry = link(child, data: { name: "Ada" })

    expect(EntityAssociationGraph.build(customer.id).primaries).not_to include(child)
    profile = profiles(project).fetch(0)
    expect(profile.entity).to eq(child)
    expect(profile.entry).to eq(entry)
    expect(profile.display.text(profile.entry, "name")).to eq("Ada")
  end

  it "ignores foreign domains, memberships, entries, and entity identities even for an owner" do
    foreign_customer = create(:customer)
    foreign_user = create(:user, :member, customer: foreign_customer)
    foreign_domain = create(:entity_domain, customer: foreign_customer, name: "Foreign")
    shared = shared_person("Shared profile")
    place(shared, foreign_domain, tenant: foreign_customer)
    foreign_entry = link(shared, account: foreign_user, tenant: foreign_customer)
    # Deliberately corrupt the link to prove the read query still requires cid.
    foreign_entry.update_column(:user_id, user.id)

    enable_module!("authentication", foreign_customer).set_extendable_model!(person_model, true)
    foreign_type = create(:entity, customer: foreign_customer, name: "Foreign profile", extended_model: person_model)
    link(foreign_type, tenant: customer)
    local = person("Local profile")
    local_entry = link(local)

    sections = project(actor: owner)

    expect(sections.map(&:domain)).to eq([nil])
    expect(profiles(sections).map(&:entity)).to eq([local, shared])
    expect(profiles(sections).map(&:entry)).to eq([local_entry, nil])
  end

  it "never infers a link from identity data, another account, or reference values" do
    entity = person("Student", property_schema: [
      { name: "Account reference", name_slug: "account_reference", html_type: "text" }
    ].to_json)
    data = { email: user.email, first_name: user.first_name, last_name: user.last_name, account_reference: user.id }
    link(entity, data: data, account: nil)
    link(entity, data: data, account: create(:user, :member, customer: customer))

    section = project.fetch(0)

    expect(section.profiles.fetch(0).entry).to be_nil
  end

  it "omits inactive, deleted, plain, and malformed bridge types while retaining an inactive account's link" do
    inactive = person("Inactive", status: :inactive)
    deleted = person("Deleted")
    deleted.soft_delete
    bridge = create(:entity, customer: customer, name: "Bridge")
    bridge.update_columns(category: Entity.categories.fetch("bridge"), extended_model: person_model)
    plain = create(:entity, customer: customer, name: "Plain")
    eligible = person("Active profile")
    [inactive, deleted, bridge, plain, eligible].each { |entity| link(entity) }
    user.update!(status: :inactive)

    sections = project

    expect(profiles(sections).map(&:entity)).to eq([eligible])
    expect(profiles(sections).first.entry.user_id).to eq(user.id)
  end

  it "rejects a user outside the URL tenant even when the viewer is the owner" do
    foreign_user = create(:user, :member, customer: create(:customer))

    expect { project(account: foreign_user, actor: owner) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "rejects members, anonymous viewers, and another tenant's admin" do
    foreign_admin = create(:user, :admin, customer: create(:customer))

    [user, nil, foreign_admin].each do |actor|
      expect { project(actor: actor) }.to raise_error(CanCan::AccessDenied)
    end
  end

  it "omits an inaccessible definition instead of projecting it as a missing link" do
    allowed = person("Allowed")
    denied = person("Denied")
    ability = Ability.new(viewer)
    ability.cannot :read, Entity, id: denied.id
    allow(Ability).to receive(:new).with(viewer).and_return(ability)

    expect(profiles(project).map(&:entity)).to eq([allowed])
  end

  it "does not project destinations whose admin routes are inaccessible" do
    person("Student")
    ability = Ability.new(viewer)
    ability.cannot :read, :route_admin_entity_entries
    allow(Ability).to receive(:new).with(viewer).and_return(ability)

    expect(project).to eq([])
  end

  it "loads explicit links in one query constrained by tenant, user, and eligible entity ids" do
    4.times { |index| link(person("Profile #{index}")) }
    queries = []
    subscriber = lambda do |*, payload|
      sql = payload[:sql].to_s
      queries << sql if sql.start_with?("SELECT") && sql.include?('FROM "entity_entries"')
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { project }

    expect(queries.size).to eq(1)
    expect(queries.first).to include('"entity_entries"."customer_id"', '"entity_entries"."user_id"', '"entity_entries"."entity_id"')
  end

  describe "field groups and display values" do
    let(:hidden) { { "admin" => false, "member" => true, "public" => true } }
    let(:groups) do
      [
        { id: "contact", name: "Contact", icon: "mail", color: "sky" },
        { id: "identity", name: "Identity", icon: "user", color: "indigo" },
        { id: "secret", name: "Hidden group", icon: "folder", color: "slate" }
      ]
    end

    it "preserves authored group and field order, filters hidden fields, and appends Other fields" do
      fields = [
        { name: "Name", name_slug: "name", html_type: "text", group_id: "identity" },
        { name: "Private", name_slug: "private", html_type: "text", group_id: "contact", visibility: hidden },
        { name: "Phone", name_slug: "phone", html_type: "tel", group_id: "contact" },
        { name: "Email", name_slug: "email", html_type: "email", group_id: "contact" },
        { name: "Secret", name_slug: "secret", html_type: "text", group_id: "secret", visibility: hidden },
        { name: "Notes", name_slug: "notes", html_type: "textarea" }
      ]
      entity = person("Student", attribute_groups: groups, property_schema: fields.to_json)
      link(entity, data: { name: "Ada", phone: "123", email: user.email, private: "Hidden", secret: "Hidden", notes: "Notes" })
      expect(Entities::EntryDisplay).to receive(:new).with(
        entity: an_instance_of(Entity), entries: an_instance_of(Array), customer_id: customer.id,
        audience: EntityAttributeAudience::ADMIN, viewer: viewer
      ).and_call_original

      profile = profiles(project).fetch(0)

      expect(profile.groups.map { |group| group[:key] }).to eq(%w[contact identity other])
      expect(profile.groups.map { |group| group[:heading] }).to eq(["Contact", "Identity", I18n.t("admin_misc.entities.entry_detail.ungrouped")])
      expect(profile.groups.first.slice(:icon, :color)).to eq(icon: "mail", color: "sky")
      expect(profile.groups.map { |group| group[:fields].map { |field| field["name_slug"] } }).to eq([%w[phone email], ["name"], ["notes"]])
      expect(profile.groups.last.slice(:icon, :color)).to eq(icon: nil, color: nil)
      expect(profile.groups).to all(have_attributes(keys: %i[key heading icon color fields]))
    end

    it "keeps a linked profile with no admin-visible fields distinct from a missing link" do
      entity = person("Student", property_schema: [
        { name: "Secret", name_slug: "secret", html_type: "text", visibility: hidden }
      ].to_json)
      entry = link(entity, data: { secret: "Hidden" })

      section = project.fetch(0)
      profile = section.profiles.fetch(0)

      expect(profile.entry).to eq(entry)
      expect(profile.display).to be_a(Entities::EntryDisplay)
      expect(profile.groups).to eq([])
    end

    it "skips legacy fields without slugs and localizes fallback headings at call time" do
      entity = person("Student")
      entity.attribute_groups_json = [{ id: "legacy", label: "Legacy label" }, { id: "unnamed" }]
      entity.property_schema_json = [
        { name: "Invalid", name_slug: "", group_id: "legacy" },
        { name: "Valid", name_slug: "valid", group_id: "legacy" },
        { name: "Fallback", name_slug: "fallback", group_id: "unnamed" },
        { name: "Other", name_slug: "other" }
      ]
      entity.save!(validate: false)
      link(entity)

      I18n.with_locale(:"zh-CN") do
        profile = profiles(project).fetch(0)
        fallback = I18n.t("admin_misc.entities.entry_detail.ungrouped")
        expect(profile.groups.map { |group| group[:heading] }).to eq(["Legacy label", fallback, fallback])
        expect(profile.groups.first[:fields].map { |field| field["name_slug"] }).to eq(["valid"])
      end
    end

    it "preserves false and zero and reads option, derived, and tenant-scoped reference labels" do
      reference_entity = create(:entity, :shared, name: "Team", property_schema: [
        { name: "Name", name_slug: "name", html_type: "text" }
      ].to_json)
      team = create(:entity_entry, customer: customer, entity: reference_entity, data: { name: "Tenant team" }.to_json)
      foreign_team = create(:entity_entry, customer: create(:customer), entity: reference_entity, data: { name: "Foreign secret" }.to_json)
      entity = person("Student", property_schema: [
        { name: "Enabled", name_slug: "enabled", html_type: "switch" },
        { name: "Seats", name_slug: "seats", html_type: "number" },
        { name: "Double seats", name_slug: "double_seats", html_type: "number", type: "Calculated", formula: "seats * 2" },
        { name: "Mode", name_slug: "mode", html_type: "select", config: { options: [{ value: "in_person", label: "In person" }] } },
        { name: "Teams", name_slug: "teams", html_type: "multi-select", config: {
          options_source: "entity_entries", entity_id: reference_entity.id.to_s, label_field: "name"
        } }
      ].to_json)
      link(entity, data: { enabled: false, seats: 0, mode: "in_person", teams: [team.id.to_s, foreign_team.id.to_s] })

      profile = profiles(project).fetch(0)

      expect(profile.display.text(profile.entry, "enabled")).to eq(I18n.t("common.labels.no"))
      expect(profile.display.text(profile.entry, "seats")).to eq("0")
      expect(profile.display.text(profile.entry, "double_seats")).to eq("0")
      expect(profile.display.text(profile.entry, "mode")).to eq("In person")
      reference_text = profile.display.text(profile.entry, "teams")
      expect(reference_text).to include("Tenant team", Entities::ReferenceLabels.missing(foreign_team.id))
      expect(reference_text).not_to include("Foreign secret")
    end
  end

  it "resolves the URL tenant's shared override and restores the surrounding Current context" do
    global_fields = [{ name: "Mode", name_slug: "mode", html_type: "select", config: { options: [{ value: "x", label: "Global label" }] } }]
    shared = shared_person("Shared student", property_schema: global_fields.to_json)
    domain = create(:entity_domain, customer: customer, name: "Tenant domain")
    place(shared, domain)
    owner_domain = create(:entity_domain, customer: owner.customer, name: "Owner domain")
    place(shared, owner_domain, tenant: owner.customer)

    [customer, owner.customer].each do |tenant|
      Current.set(customer: tenant, shared_resources_mode: false) do
        definition = Entity.find(shared.id)
        definition.attribute_groups_json = [{ id: "tenant", name: tenant == customer ? "Tenant group" : "Owner group", icon: "user", color: "teal" }]
        definition.property_schema_json = [global_fields.first.deep_stringify_keys.deep_merge(
          "group_id" => "tenant", "config" => { "options" => [{ "value" => "x", "label" => tenant == customer ? "Tenant label" : "Owner label" }] }
        )]
        definition.save!(validate: false)
      end
    end
    entry = link(shared, data: { mode: "x" })
    Current.customer = owner.customer
    Current.user = owner
    Current.shared_resources_mode = true

    sections = project(actor: owner)
    profile = sections.fetch(0).profiles.fetch(0)

    expect(sections.map(&:domain)).to eq([domain])
    expect(profile.entity.attribute_groups_json.first["name"]).to eq("Tenant group")
    expect(profile.groups.first[:heading]).to eq("Tenant group")
    expect(profile.entry).to eq(entry)
    expect(profile.entry.entity).to equal(profile.entity)
    expect(profile.display.text(profile.entry, "mode")).to eq("Tenant label")
    expect(Current.customer).to eq(owner.customer)
    expect(Current.user).to eq(owner)
    expect(Current.shared_resources_mode).to be(true)
    Current.set(customer: nil, shared_resources_mode: false) do
      expect(Entity.find(shared.id).property_schema_json.first.dig("config", "options", 0, "label")).to eq("Global label")
    end
  end
end
