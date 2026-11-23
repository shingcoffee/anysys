# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::EditorComponent, type: :component do
  include JourneyPageHelpers
  include_context "student course association"

  let(:customer) { create(:customer) }
  let(:start_page) { student_journey_page(name: "Student form") }
  let(:course_page) { course_journey_page }
  let(:pages) { [course_page, start_page] }
  let(:domain) { create(:entity_domain, customer: customer, name: "School") }
  let(:catalog) { Journeys::BuilderCatalog.new(pages: pages, domain: domain, customer_id: customer.id) }
  let(:journey) { create(:journey, customer: customer, entity_domain: domain, name: "Enrolment", description: "Enrol a student") }
  let(:base) { "/#{customer.id}/admin/maintenance/entities/journeys" }
  let(:domain_workspace) { "/#{customer.id}/admin/maintenance/entities?domain_id=#{domain.id}" }

  before { Current.customer = customer }
  after { Current.reset }

  def render_editor(record = journey, **options)
    render_inline(described_class.new(journey: record, customer_id: customer.id, catalog: catalog, domains: [domain], **options))
  end

  def rows = page.all("[data-journey-builder-target='list'] > [data-journey-builder-target='row']")
  def finish = page.find("[data-journey-builder-target='row'][data-finish]")
  def builder = page.find("[data-controller='journey-builder']")

  it "renders the journey details beside the steps in an owner form" do
    render_editor

    form = page.find("form#journey-form[action='#{base}/#{journey.id}']")
    details = form.find("section[aria-labelledby='journey-details-title']")
    expect(details).to have_css("h2", text: I18n.t("journeys.admin.sections.details"))
    expect(details).to have_field("journey[name]", with: "Enrolment")
    expect(details).to have_field("journey[key]", with: journey.key)
    expect(details.find_field("journey[key]")["aria-describedby"]).to eq("journey-key-hint")
    expect(details).to have_field("journey[description]", with: "Enrol a student")
    expect(details).to have_select("journey[entity_domain_id]", selected: "School", options: ["School"])
    expect(details.find("select[name='journey[entity_domain_id]']")["required"]).to be_present
    expect(details).to have_checked_field(I18n.t("journeys.audiences.admin"))
    expect(details).to have_unchecked_field(I18n.t("journeys.audiences.member"))
    expect(details).not_to have_css("[data-role='journey-start-link']")
    expect(page).to have_css("h1", text: "Enrolment")
    expect(page).to have_css(".badge", text: I18n.t("journeys.admin.status.draft"))
  end

  it "titles the page after the saved name while a rename is refused" do
    journey.name = ""
    render_editor

    expect(page).to have_css("h1", text: "Enrolment")
  end

  it "links the breadcrumbs through Maintenance / Entities / the journey's domain" do
    render_editor

    crumbs = page.find("nav", match: :first)
    expect(crumbs).to have_link(I18n.t("maint_core.nav.entities"), href: "/#{customer.id}/admin/maintenance/entities")
    expect(crumbs).to have_link("School", href: domain_workspace)
  end

  it "asks for a domain on a new journey, keeping the one it was opened from" do
    render_editor(Journey.new(customer: customer, audience_admin: true))
    expect(page).to have_select("journey[entity_domain_id]",
                                options: [I18n.t("maint_core.entities.form.domain_prompt"), "School"])

    render_editor(Journey.new(customer: customer, audience_admin: true, entity_domain: domain))
    expect(page).to have_select("journey[entity_domain_id]", selected: "School")
    expect(page).to have_link(I18n.t("common.actions.cancel"), href: domain_workspace)
  end

  it "renders one timeline row per page step, then the fixed finish row and a blank template" do
    render_editor

    expect(rows.size).to eq(2)
    expect(rows.map { |row| row["class"] }).to all(include("group/step", "[counter-increment:journey-step]"))
    expect(rows.map { |row| row.first("input, select", visible: :all)["name"] }).to all(eq("journey[steps][][key]"))
    expect(rows.map { |row| row.find("[data-step-key]", visible: :all).value }).to eq(%w[start relate_1])
    expect(rows[0]["data-step-mode"]).to eq("create")
    expect(rows[1]["data-step-mode"]).to eq("relate")
    expect(finish.first("input, select", visible: :all)["name"]).to eq("journey[steps][][key]")
    expect(finish.find("[data-step-key]", visible: :all).value).to eq("finish")
    expect(page).to have_css("ol.\\[counter-reset\\:journey-step\\]")
    template = rendered_content[%r{<template data-journey-builder-target="template">.*?</template>}m]
    expect(template).to include('data-step-key="true"', 'name="journey[steps][][key]" value=""', 'data-step-mode="none"')
    expect(template).not_to include("data-finish")
    expect(rendered_content).to include('data-journey-builder-target="inputTemplate"')
  end

  it "groups pages by record type and publishes per-page wiring for the builder" do
    render_editor

    expect(rows[0]).to have_css("optgroup[label='#{student_entity.display_label}'] option", text: "Student form", visible: :all)
    expect(rows[0]).to have_css("optgroup[label='#{bridge_entity.display_label}'] option", text: course_page.name, visible: :all)
    expect(builder["data-journey-builder-none-value"]).to eq(I18n.t("journeys.admin.step_fill_none"))
    payload = JSON.parse(builder["data-journey-builder-pages-value"])
    expect(payload.keys).to contain_exactly(start_page.id.to_s, course_page.id.to_s)
    expect(payload[start_page.id.to_s]).to include(
      "entity" => student_entity.id.to_s,
      "hint" => a_string_including(student_entity.display_label, I18n.t("journeys.audiences.admin"), I18n.t("journeys.admin.page_hint.adds_records")),
      "inputs" => []
    )
    student_input = payload[course_page.id.to_s]["inputs"].find { |input| input["field"] == "student" }
    expect(student_input).to include("entity" => student_entity.id.to_s,
                                     "label" => I18n.t("journeys.admin.step_fill_from", field: "Student"))
    expect(payload[course_page.id.to_s]["hint"]).to include(I18n.t("journeys.admin.page_hint.locks", fields: "Student"))
    expect(page).to have_text(I18n.t("journeys.admin.sections.steps_flow_hint"))
  end

  it "selects each step's page, fill source and repeat flag, naming steps by their page" do
    render_editor

    expect(rows[0]).to have_select("journey[steps][][page_id]", selected: "Student form", visible: :all)
    relate = rows[1]
    expect(relate).to have_select("journey[steps][][page_id]", selected: course_page.name, visible: :all)
    fill = relate.find("select[name='journey[steps][][inputs][student]']", visible: :all)
    expect(fill.value).to eq("start")
    expect(fill).to have_css("option[value='']", text: I18n.t("journeys.admin.step_fill_none"), visible: :all)
    expect(fill).to have_css("option[value='start']", text: "Student form", visible: :all)
    expect(relate).to have_checked_field("journey[steps][][repeat]", visible: :all)
    expect(relate).to have_unchecked_field("journey[steps][][optional]", visible: :all)
    expect(relate).not_to have_css("input[type='hidden'][name='journey[steps][][repeat]']", visible: :all)
    expect(relate).not_to have_css("input[type='hidden'][name='journey[steps][][optional]']", visible: :all)
    expect(page).not_to have_css("select[name='journey[steps][][input_from]']", visible: :all)
    expect(finish).to have_checked_field("journey[steps][][finish_kind]", with: "record", visible: :all)
    expect(finish).to have_unchecked_field("journey[steps][][finish_kind]", with: "page", visible: :all)
    expect(finish).to have_select("journey[steps][][finish_step]", selected: "Student form",
                                                                     options: ["Student form", course_page.name], visible: :all)
  end

  it "names an unlabelled step without a page by its number, and a labelled one by its label" do
    record = create(:journey, customer: customer, entity_domain: domain, definition: {
      "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "missing_page" },
        { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "label" => "Courses",
          "inputs" => { "student" => "start" } },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "page", "action_key" => "student_new" } }
      ]
    }.to_json)
    render_editor(record)

    step_one = I18n.t("journeys.admin.step_number", number: 1)
    expect(finish).to have_select("journey[steps][][finish_step]", options: [step_one, "Courses"], visible: :all)
    expect(finish).to have_checked_field("journey[steps][][finish_kind]", with: "page", visible: :all)
    expect(finish).to have_select("journey[steps][][finish_page_id]", selected: "Student form", visible: :all)
  end

  it "wires the builder actions and lets CSS show fields by position, mode and finish destination" do
    render_editor

    expect(builder["data-journey-builder-step-name-value"]).to eq(I18n.t("journeys.admin.step_number", number: "{number}"))
    expect(builder).to have_css("button[data-action='journey-builder#add']", text: I18n.t("journeys.admin.add_step"))
    row = rows[1]
    expect(row).to have_css("button[data-action='journey-builder#moveUp'][aria-label='#{I18n.t('journeys.admin.move_up')}']")
    expect(row).to have_css("button[data-action='journey-builder#moveUp'][class*='group-first/step:invisible']")
    expect(row).to have_css("button[data-action='journey-builder#moveDown'][class*='group-last/step:invisible']")
    expect(row).to have_css("button[data-action='journey-builder#remove']")
    expect(row).to have_css("select[data-step-page][data-action='change->journey-builder#pageChanged'][aria-describedby]", visible: :all)
    expect(row).to have_css("input[data-step-label][data-action='input->journey-builder#refresh']", visible: :all)
    expect(row).to have_css("[class*='group-data-[step-lead]/step:hidden'] [data-step-inputs-section]", visible: :all)
    expect(row).to have_css("[class*='group-data-[step-lead]/step:inline']", text: I18n.t("journeys.admin.step_start"), visible: :all)
    expect(rows.map { |item| item["data-step-lead"] }).to eq(["", nil])
    expect(row).to have_css("input[data-step-optional][data-action='change->journey-builder#refresh']", visible: :all)
    expect(finish).to have_css("input[type='radio'][data-finish-page][value='page']", visible: :all)
    expect(finish).to have_css("[class*='group-has-[[data-finish-page]:checked]/finish:block'] select[name='journey[steps][][finish_page_id]']",
                               visible: :all)
    kind = row.find("select[name='journey[steps][][kind]'][data-step-kind][data-action='change->journey-builder#kindChanged']", visible: :all)
    expect(kind).to have_css("option[value='add'][selected]", text: I18n.t("journeys.admin.step_kind.add"), visible: :all)
    expect(kind).to have_css("option[value='update']", text: I18n.t("journeys.admin.step_kind.update"), visible: :all)
    expect(row).to have_css("label[class*='group-data-[step-lead]/step:hidden'] [data-step-kind]", visible: :all)
    expect(row).to have_css("[class*='group-data-[step-mode=update]/step:block'] select[name='journey[steps][][record]'][data-step-record]",
                            visible: :all)
    expect(finish).not_to have_css("[data-step-kind]", visible: :all)
  end

  context "with a step that edits a record an earlier step saved" do
    let(:review_journey) do
      create(:journey, customer: customer, entity_domain: domain, definition: {
        "steps" => [
          { "key" => "start", "kind" => "create", "action_key" => "student_new" },
          { "key" => "review", "kind" => "update", "action_key" => "student_new", "record" => "start", "optional" => true },
          { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
        ]
      }.to_json)
    end

    it "sets the row to edit a record, offers only pages that edit records, and picks the record it edits" do
      render_editor(review_journey)

      review = rows[1]
      expect(review["data-step-mode"]).to eq("update")
      expect(review).to have_select("journey[steps][][kind]", selected: I18n.t("journeys.admin.step_kind.update"), visible: :all)
      expect(review).to have_css("option[value='#{start_page.id}'][selected]", visible: :all)
      expect(review).to have_css("option[value='#{course_page.id}'][disabled][hidden]", visible: :all)
      record = review.find("select[name='journey[steps][][record]']", visible: :all)
      expect([record["data-step-input-entity"], record.value]).to eq([student_entity.id.to_s, "start"])
      expect(record).to have_css("option[value='start']", text: "Student form", visible: :all)
      expect(record["aria-describedby"]).to eq("journey-step-hint-review-record")
      expect(review).to have_css("p#journey-step-hint-review-record[data-step-record-hint]", text: I18n.t("journeys.admin.step_record_hint"),
                                                                                              visible: :all)
      expect(review).to have_checked_field("journey[steps][][optional]", visible: :all)
      expect(rows[0]).to have_select("journey[steps][][kind]", selected: I18n.t("journeys.admin.step_kind.add"), visible: :all)
      expect(rows[0]).not_to have_css("option[disabled]", visible: :all)
      updates = JSON.parse(builder["data-journey-builder-pages-value"]).transform_values { |wiring| wiring["updates"] }
      expect(updates).to eq(start_page.id.to_s => true, course_page.id.to_s => false)
    end

    it "keeps a posted kind and record on a refused save, but never lets the lead row edit" do
      render_editor(review_journey, submitted_steps: [{ "kind" => "update", "page_id" => start_page.id.to_s },
                                                      { "kind" => "update", "page_id" => course_page.id.to_s, "record" => "gone" }, {}])

      expect(rows[0]["data-step-mode"]).to eq("create")
      expect(rows[0]).to have_select("journey[steps][][kind]", selected: I18n.t("journeys.admin.step_kind.add"), visible: :all)
      review = rows[1]
      expect(review["data-step-mode"]).to eq("update")
      expect(review).to have_css("option[value='#{course_page.id}'][selected]:not([disabled])", visible: :all)
      record = review.find("select[name='journey[steps][][record]']", visible: :all)
      expect([record["data-step-input-entity"], record.value]).to eq([bridge_entity.id.to_s, ""])
    end
  end

  it "offers delete, duplicate, preview and launch in the header, a create-page link, and save in the footer" do
    render_editor(preview_path: "/preview?journey=enrol")

    expect(page).to have_button(I18n.t("journeys.admin.save"), count: 1)
    expect(page).to have_link(I18n.t("common.actions.cancel"), href: domain_workspace)
    expect(page).to have_css("a[href='#{base}/#{journey.id}/launch'][data-turbo-method='post']", text: I18n.t("journeys.admin.launch"))
    expect(page).to have_css("a[href='#{base}/#{journey.id}/copy'][data-turbo-method='post']", text: I18n.t("journeys.admin.duplicate"))
    expect(page).to have_link(I18n.t("journeys.admin.preview"), href: "/preview?journey=enrol")
    expect(page.find_link(I18n.t("journeys.admin.preview"))["target"]).to eq("_blank")
    expect(page).not_to have_link(I18n.t("journeys.admin.generate"))
    create_page = page.find_link(I18n.t("journeys.admin.create_page"))
    expect([create_page["href"], create_page["target"]]).to eq(["/#{customer.id}/admin/maintenance/pages/new", "_blank"])
    delete = page.find_link(I18n.t("journeys.admin.delete"))
    expect([delete["data-turbo-method"], delete["data-turbo-confirm"]]).to eq(["delete", I18n.t("journeys.admin.delete_confirm")])
  end

  it "offers take offline and the start link for a launched journey, and no preview without a path" do
    journey.update!(status: :launched)
    render_editor

    expect(page).to have_css("a[href$='/launch'][data-turbo-method='delete']", text: I18n.t("journeys.admin.take_offline"))
    expect(page).not_to have_link(I18n.t("journeys.admin.preview"))
    link = page.find("[data-role='journey-start-link'] a")
    expect(link[:href]).to end_with("/#{customer.id}/journeys/#{journey.key}")
    expect(link[:target]).to eq("_blank")
  end

  it "seeds one page step and the finish for a new journey, wires slugify, and offers generate" do
    record = Journey.new(customer: customer, audience_admin: true, entity_domain: domain)
    render_editor(record)

    expect(page.find("form#journey-form")["action"]).to eq(base)
    expect(page).to have_css("h1", text: I18n.t("journeys.admin.new"))
    expect(rows.map { |row| row.find("[data-step-key]", visible: :all).value }).to eq(%w[step_1])
    expect(finish.find("[data-step-key]", visible: :all).value).to eq("finish")
    expect(page).not_to have_css(".badge", text: I18n.t("journeys.admin.status.draft"))
    expect(page).not_to have_link(I18n.t("journeys.admin.launch"))
    expect(page).not_to have_link(I18n.t("journeys.admin.delete"))
    expect(page).not_to have_link(I18n.t("journeys.admin.duplicate"))
    expect(page).to have_link(I18n.t("journeys.admin.generate"),
                              href: "#{base}/generate?domain_id=#{domain.id}")
    details = page.find("section[aria-labelledby='journey-details-title']")
    expect(details["data-controller"]).to eq("template-slugify")
    expect(details).to have_css("[data-template-slugify-target='name'][data-action='input->template-slugify#suggest']")
    expect(details).to have_css("[data-template-slugify-target='key']")
  end

  it "does not wire slugify on a persisted journey" do
    render_editor

    expect(page.find("section[aria-labelledby='journey-details-title']")["data-controller"]).to be_blank
    expect(page).not_to have_css("[data-template-slugify-target]")
  end

  it "opens the timeline with a new-record start and lists the record types a journey could start from" do
    render_editor

    start = page.find("[data-role='journey-start'] > fieldset")
    expect(start).to have_checked_field("journey[start][kind]", with: "create", visible: :all)
    expect(start).to have_unchecked_field("journey[start][kind]", with: "record", visible: :all)
    expect(start).to have_css("input[value='record'][data-start-record][data-journey-builder-target='startKind']" \
                              "[data-action='change->journey-builder#refresh']", visible: :all)
    expect(start).to have_select("journey[start][entity_id]", options: [I18n.t("journeys.admin.start.entity_prompt"), "Course", "Student"],
                                                              visible: :all)
    expect(start).not_to have_css("select[name='journey[start][entity_id]'] option[selected]", visible: :all)
    expect(start).to have_css("[class*='group-has-[[data-start-record]:checked]/start:block'] select[data-journey-builder-target='startEntity']",
                              visible: :all)
    expect(start.find("input[name='journey[start][key]']", visible: :all).value).to eq("record")
    expect(builder["data-journey-builder-record-name-value"]).to eq(I18n.t("journeys.admin.start.record_name", entity: "{entity}"))
  end

  context "when the journey starts from an existing record" do
    let(:record_journey) do
      create(:journey, customer: customer, entity_domain: domain, definition: {
        "steps" => [
          { "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s },
          { "key" => "courses", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "record" }, "repeat" => true },
          { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "record" } }
        ]
      }.to_json)
    end
    let(:record_name) { I18n.t("journeys.admin.start.record_name", entity: "Student") }

    it "selects the record type, leads with no row, and offers the record to the fill and finish pickers" do
      render_editor(record_journey)

      start = page.find("[data-role='journey-start']")
      expect(start).to have_checked_field("journey[start][kind]", with: "record", visible: :all)
      expect(start).to have_select("journey[start][entity_id]", selected: "Student", visible: :all)
      expect(rows.size).to eq(1)
      expect(rows[0]["data-step-lead"]).to be_nil
      fill = rows[0].find("select[name='journey[steps][][inputs][student]']", visible: :all)
      expect(fill.value).to eq("record")
      expect(fill).to have_css("option[value='record']", text: record_name, visible: :all)
      expect(finish).to have_select("journey[steps][][finish_step]", selected: record_name, options: [record_name, course_page.name],
                                                                     visible: :all)
    end

    it "explains there is no start link once launched" do
      record_journey.update!(status: :launched)
      render_editor(record_journey)

      expect(page).to have_css("[data-role='journey-start-link']", text: I18n.t("journeys.admin.start.no_link"))
      expect(page).not_to have_css("[data-role='journey-start-link'] a")
    end

    context "with a start condition" do
      let(:any_record) { I18n.t("journeys.admin.start.when_any") }

      before do
        student_entity.property_schema_json = Array(student_entity.property_schema_json) + [{
          "name" => "Stage", "name_slug" => "stage", "html_type" => "select",
          "config" => { "options" => [{ "label" => "Applied", "value" => "applied" }, { "label" => "Admitted", "value" => "admitted" }] }
        }]
        student_entity.save!
      end

      def condition = page.find("[data-role='journey-start-when']", visible: :all)
      def values = condition.find("[data-journey-builder-target='whenValues']", visible: :all)
      def boxes = values.all("input[type='checkbox'][name='journey[start][when][in][]'][data-when-value]", visible: :all)
                        .map { |box| [box.value, box.checked?] }

      it "shows the checked field and values, keeping a saved value the field no longer offers" do
        definition = JSON.parse(record_journey.definition)
        definition["steps"][0]["when"] = { "field" => "stage", "in" => %w[admitted retired] }
        record_journey.update!(definition: definition.to_json)
        render_editor(record_journey)

        expect(condition["class"]).to include("group-has-[[data-start-record]:checked]/start:block")
        field = condition.find("select[name='journey[start][when][field]'][data-journey-builder-target='whenField']", visible: :all)
        expect(field["data-action"]).to eq("change->journey-builder#whenFieldChanged")
        expect(condition).to have_select("journey[start][when][field]", options: [any_record, "Stage"], selected: "Stage", visible: :all)
        expect(values["hidden"]).to be_nil
        expect(boxes).to eq([["applied", false], ["admitted", true], ["retired", true]])
        expect(values).to have_css("label span[data-when-value-label]", text: "Admitted", visible: :all)
        expect(condition).to have_css("#journey-start-when-hint", text: I18n.t("journeys.admin.start.when_hint"), visible: :all)
        template = rendered_content[%r{<template data-journey-builder-target="whenValueTemplate">.*?</template>}m]
        expect(template).to include('name="journey[start][when][in][]"', 'value=""', "data-when-value-label")
      end

      it "publishes each record type's choice fields and their stored values for the builder" do
        render_editor(record_journey)

        choices = JSON.parse(builder["data-journey-builder-choices-value"])
        expect(choices[student_entity.id.to_s]).to eq([{ "field" => "stage", "label" => "Stage", "options" => [
          { "value" => "applied", "label" => "Applied", "sources" => "" },
          { "value" => "admitted", "label" => "Admitted", "sources" => "" }
        ] }])
        expect(choices[course_entity.id.to_s]).to eq([])
        expect(condition).to have_select("journey[start][when][field]", options: [any_record, "Stage"], visible: :all)
        expect(condition).not_to have_css("option[selected]", visible: :all)
        expect(values["hidden"]).not_to be_nil
        expect(boxes).to eq([])
      end

      it "keeps a posted condition, and a saved field the record type no longer has, on a refused save" do
        render_editor(submitted_start: { "kind" => "record", "entity_id" => student_entity.id.to_s, "key" => "",
                                         "when" => { "field" => "stage", "in" => ["applied"] } })
        expect(boxes).to eq([["applied", true], ["admitted", false]])

        render_editor(submitted_start: { "kind" => "record", "entity_id" => student_entity.id.to_s, "key" => "",
                                         "when" => { "field" => "gone", "in" => ["x"] } })
        expect(condition).to have_select("journey[start][when][field]", options: [any_record, "Stage", "gone"], selected: "gone",
                                                                        visible: :all)
        expect(boxes).to eq([["x", true]])
      end
    end
  end

  context "with journeys handing records on to each other" do
    include_context "booking journeys"

    let(:catalog) do
      Journeys::BuilderCatalog.new(pages: [request_page, review_page, pay_page], domain: booking_domain, customer_id: customer.id, journey: pay_journey)
    end

    def render_pay = render_inline(described_class.new(journey: pay_journey, customer_id: customer.id, catalog: catalog, domains: [booking_domain]))
    def reached_in(journey, step) = I18n.t("journeys.admin.handoffs.reached_in", sources: I18n.t("journeys.admin.handoffs.source", journey: journey, step: step))

    it "notes under each start-condition value which other journeys' steps leave records in it" do
      render_pay

      notes = page.all("[data-journey-builder-target='whenValues'] label", visible: :all).to_h do |label|
        [label.find("[data-when-value-label]", visible: :all).text, label.find("[data-when-value-sources]", visible: :all).text]
      end
      expect(notes).to eq("Requested" => reached_in("Request a booking", "Booking details"), "Approved" => reached_in("Review a booking", "Review form"),
                          "Declined" => reached_in("Review a booking", "Review form"), "Paid" => "")
      options = JSON.parse(builder["data-journey-builder-choices-value"]).fetch(booking.id.to_s).sole["options"]
      expect(options.find { |option| option["value"] == "approved" }["sources"]).to eq(reached_in("Review a booking", "Review form"))
      template = rendered_content[%r{<template data-journey-builder-target="whenValueTemplate">.*?</template>}m]
      expect(template).to include("data-when-value-sources")
    end

    it "publishes each page's On submit lines and the wording the builder needs for skippable steps" do
      render_pay

      effects = JSON.parse(builder["data-journey-builder-pages-value"]).fetch(request_page.id.to_s)["effects"]
      expect(effects).to include("lines" => [I18n.t("journeys.admin.effects.saves_only")],
                                 "creating" => [I18n.t("journeys.admin.effects.starts_in", entity: "Booking", field: "Status", state: "Requested")],
                                 "skips" => [], "path" => "/#{customer.id}/admin/maintenance/pages/#{request_page.id}")
      expect(effects["nextCreating"].sole).to include("Review a booking")
      expect(builder["data-journey-builder-skipped-by-value"]).to eq(I18n.t("journeys.admin.step_conditional_by", steps: "{steps}"))
      expect(builder["data-journey-builder-skipped-none-value"]).to eq(I18n.t("journeys.admin.step_conditional_none"))
      expect(builder["data-journey-builder-separator-value"]).to eq(I18n.t("journeys.admin.effects.separators.list"))
      expect(rows.sole).to have_css("[data-step-effects] li", text: I18n.t("journeys.admin.effects.paid_move", field: "Status", state: "Paid"), visible: :all)
    end
  end

  context "when the journey starts by creating a user account" do
    let(:user_journey) do
      create(:journey, customer: customer, entity_domain: domain, definition: {
        "steps" => [
          { "key" => "account", "kind" => "user" },
          { "key" => "start", "kind" => "create", "action_key" => "student_new" },
          { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
        ]
      }.to_json)
    end

    it "checks the user start, keeps its key, and leads with the person page" do
      render_editor(user_journey)

      start = page.find("[data-role='journey-start']")
      expect(start).to have_checked_field("journey[start][kind]", with: "user", visible: :all)
      expect(start).to have_css("input[value='user'][data-start-user][data-journey-builder-target='startKind']", visible: :all)
      expect(start.find("input[name='journey[start][key]']", visible: :all).value).to eq("account")
      expect(start).to have_css("[data-role='journey-start-user-hint'][class*='group-has-[[data-start-user]:checked]/start:block']",
                                text: I18n.t("journeys.admin.start.user_hint"), visible: :all)
      expect(rows.size).to eq(1)
      expect(rows[0]["data-step-lead"]).not_to be_nil
      expect(finish).to have_select("journey[steps][][finish_step]", options: ["Student form"], visible: :all)
    end

    it "defaults a posted user start's key" do
      render_editor(submitted_start: { "kind" => "user", "key" => "" })

      expect(page).to have_checked_field("journey[start][kind]", with: "user", visible: :all)
      expect(page.find("input[name='journey[start][key]']", visible: :all).value).to eq("user")
    end
  end

  it "keeps a posted record start on a refused save" do
    render_editor(submitted_start: { "kind" => "record", "entity_id" => course_entity.id.to_s, "key" => "" })

    expect(page).to have_checked_field("journey[start][kind]", with: "record", visible: :all)
    expect(page).to have_select("journey[start][entity_id]", selected: "Course", visible: :all)
    expect(page.find("input[name='journey[start][key]']", visible: :all).value).to eq("record")
    expect(rows[0]["data-step-lead"]).to be_nil
  end

  it "keeps the posted page choices on a refused save" do
    render_editor(submitted_steps: [{ "page_id" => course_page.id.to_s }, {}, { "finish_page_id" => start_page.id.to_s }])

    expect(rows[0]).to have_select("journey[steps][][page_id]", selected: course_page.name, visible: :all)
    expect(finish).to have_select("journey[steps][][finish_page_id]", selected: "Student form", visible: :all)
  end

  it "wraps details and readiness in the sticky right column, hiding the card when issues are omitted" do
    render_editor
    column = page.find("[class*='lg:col-start-3']")
    expect(column[:class]).to include("lg:sticky", "lg:top-6", "lg:row-start-1", "space-y-6")
    expect(column).to have_css("section[aria-labelledby='journey-details-title']")
    expect(page).not_to have_css("#journey-readiness-title")

    render_editor(readiness: [])
    expect(page.find("[class*='lg:col-start-3']")).to have_css("#journey-readiness-title")
    expect(page).to have_css("[role='status']", text: I18n.t("journeys.admin.readiness.ready"))

    render_editor(readiness: ["Finish: choose where the journey ends."])
    expect(page).to have_css("#journey-readiness-title + p", text: I18n.t("journeys.admin.readiness.issues"))
    expect(page).to have_css("[role='list']", text: "Finish: choose where the journey ends.")
  end

  it "shows the errors it is given" do
    render_editor(errors: ["Finish: choose where the journey ends."])

    expect(page).to have_css("[role='alert']", text: "Finish: choose where the journey ends.")
  end

  it "renders in zh-CN" do
    I18n.with_locale(:"zh-CN") { render_editor }

    expect(page).to have_text("业务域")
    expect(page).to have_text("基本信息")
    expect(page).to have_button("保存")
  end
end
