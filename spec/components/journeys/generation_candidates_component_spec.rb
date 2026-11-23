# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::GenerationCandidatesComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:school) { create(:entity_domain, customer: customer, name: "School") }
  let(:clubs) { create(:entity_domain, customer: customer, name: "Clubs") }
  let(:entity_class) do
    Struct.new(:display_label, :person) do
      def person? = person == true
    end
  end
  let(:planner) { EntityDomains::JourneyPlanner }

  def step(label) = planner::RelateStep.new(entity: nil, parent_slug: "student", label: label, link: true, page_key: "x")

  def candidate(key, kind:, start:, steps: [], audience: "admin", left_out: [], journey_key: "#{key}_journey", person: false, follow: nil)
    planner::Candidate.new(key: key, kind: kind, audience: audience, start: entity_class.new(start, person), steps: steps.map { |label| step(label) },
                           name: "#{start} #{kind}", page_key: nil, journey_key: journey_key, left_out: left_out, follow: follow)
  end

  let(:school_candidates) do
    [candidate("create-1", kind: :create, start: "Student", steps: %w[Course Club], journey_key: "student_journey"),
     candidate("create-2", kind: :create, start: "Course"),
     candidate("record-1", kind: :record, start: "Student", steps: ["Course"]),
     candidate("member-3", kind: :member, start: "Enrolment", audience: "member",
                           left_out: [{ "name" => "Grade", "name_slug" => "grade" }, { "name_slug" => "enrolled_on" }])]
  end

  def render_candidates(journeys: [])
    render_inline(described_class.new(groups: [[school, school_candidates], [clubs, [candidate("create-9", kind: :create, start: "Club", journey_key: "club_journey")]]],
                                      customer_id: customer.id, journeys: journeys))
  end

  def card(key) = page.find("[data-role='generation-candidate'][data-candidate='#{key}']")

  it "groups candidates by domain and then by where they start, each kind explained" do
    render_candidates

    domains = page.all("[data-role='generation-domain']")
    expect(domains.map { |group| group.find("h2").text.squish }).to eq(["School 4", "Clubs 1"])
    kinds = domains.first.all("[data-role='generation-kind']")
    expect(kinds.map { |kind| kind["data-kind"] }).to eq(%w[create record member])
    expect(kinds.first).to have_css("h3##{"journey-domain-#{school.id}-create"}", text: I18n.t("journeys.admin.generation.kinds.create.title"))
    expect(kinds.first).to have_text(I18n.t("journeys.admin.generation.kinds.create.hint"))
    expect(kinds.first["aria-labelledby"]).to eq("journey-domain-#{school.id}-create")
    expect(kinds.first.all("[data-role='generation-candidate']").map { |item| item["data-candidate"] }).to eq(%w[create-1 create-2])
    expect(domains.last.all("[data-role='generation-kind']").map { |kind| kind["data-kind"] }).to eq(%w[create])
  end

  it "shows each card's audience, start, steps and step count, posting its domain and candidate key" do
    render_candidates

    create = card("create-1")
    expect(create).to have_css(".badge", text: I18n.t("journeys.audiences.admin"))
    expect(create).to have_text("Student create")
    expect(create).to have_text(I18n.t("journeys.admin.generation.starts.create", entity: "Student"))
    expect(create.find("ul")["aria-label"]).to eq(I18n.t("journeys.admin.generation.then_steps", steps: "Course and Club"))
    expect(create).to have_css("li", text: "Club")
    expect(create).to have_text(I18n.t("journeys.admin.step_count", count: 3))
    form = create.find("form[action='/#{customer.id}/admin/maintenance/entities/journeys/generate'][method='post']")
    expect(form).to have_field("domain_id", type: :hidden, with: school.id.to_s)
    expect(form).to have_field("candidate", type: :hidden, with: "create-1")
    expect(form).to have_button(I18n.t("journeys.admin.generation.submit"))

    expect(card("create-2")).to have_text(I18n.t("journeys.admin.generation.opens_record"))
    expect(card("record-1")).to have_text(I18n.t("journeys.admin.generation.starts.record", entity: "Student"))
    expect(card("create-9").find("form")).to have_field("domain_id", type: :hidden, with: clubs.id.to_s)
  end

  it "marks member journeys and lists the fields their page leaves to admins" do
    render_candidates

    member = card("member-3")
    expect(member).to have_css(".badge", text: I18n.t("journeys.audiences.member"))
    expect(member).to have_text(I18n.t("journeys.admin.generation.starts.member"))
    expect(member.find("[data-role='generation-left-out']").text)
      .to eq(I18n.t("journeys.admin.generation.left_to_admins", fields: "Grade#{I18n.t('support.array.words_connector')}enrolled_on"))
    expect(card("create-1")).not_to have_css("[data-role='generation-left-out']")
  end

  it "links each card to the latest journey generated from it in that domain" do
    older = create(:journey, customer: customer, entity_domain: school, key: "student_journey")
    newer = create(:journey, customer: customer, entity_domain: school, key: "student_journey_2", status: :launched)
    elsewhere = create(:journey, customer: customer, entity_domain: school, key: "club_journey")
    render_candidates(journeys: [older, newer, elsewhere])

    existing = card("create-1")
    expect(existing).to have_css("[data-role='generation-existing']",
                                 text: I18n.t("journeys.admin.generation.generated", status: I18n.t("journeys.admin.status.launched")))
    expect(existing.find("[data-role='generation-open']")[:href])
      .to eq("/#{customer.id}/admin/maintenance/entities/journeys/#{newer.id}/edit")
    expect(card("create-2")).not_to have_css("[data-role='generation-existing']")
    expect(card("create-9")).not_to have_css("[data-role='generation-open']")
  end

  context "when the domain has a person" do
    let(:member) { candidate("member-3", kind: :member, start: "Note", audience: "member") }
    let(:person_candidates) do
      [candidate("create-1", kind: :create, start: "Student", steps: %w[Course], person: true),
       member,
       candidate("public-3", kind: :public, start: "Student", audience: "public", person: true, follow: member),
       candidate("public-1", kind: :public, start: "Student", audience: "public", person: true)]
    end

    before { render_inline(described_class.new(groups: [[school, person_candidates]], customer_id: customer.id)) }

    it "opens the person's create journey with its user account, counting that step" do
      create = card("create-1")

      expect(create).to have_text(I18n.t("journeys.admin.generation.starts.user", entity: "Student"))
      expect(create).to have_text(I18n.t("journeys.admin.step_count", count: 3))
    end

    it "groups public sign-ups last, naming the member page each continues on" do
      expect(page.all("[data-role='generation-kind']").map { |kind| kind["data-kind"] }).to eq(%w[create member public])
      expect(page).to have_text(I18n.t("journeys.admin.generation.kinds.public.hint"))

      follow = card("public-3")
      expect(follow).to have_css(".badge", text: I18n.t("journeys.audiences.public"))
      expect(follow).to have_text(I18n.t("journeys.admin.generation.starts.public", entity: "Student"))
      expect(follow).to have_text(I18n.t("journeys.admin.generation.continues_as_member", name: "Note member"))
      expect(follow).to have_text(I18n.t("journeys.admin.step_count", count: 1))
      expect(card("public-1")).to have_text(I18n.t("journeys.admin.generation.signup_done"))
    end
  end

  it "shows the empty state when no domain has anything to generate" do
    render_inline(described_class.new(groups: [], customer_id: customer.id))

    expect(page).to have_text(I18n.t("journeys.admin.generation.empty_title"))
    expect(page).to have_text(I18n.t("journeys.admin.generation.empty_description"))
    expect(page).not_to have_css("form")
  end
end
