# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::FormHealth do
  let_it_be(:customer) { create(:customer) }

  around { |example| Current.set(customer: customer) { example.run } }

  let(:name_attribute) { { "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" } }
  let(:motto_attribute) do
    { "name" => "Motto", "name_slug" => "motto", "type" => "String", "html_type" => "text",
      "validators" => [{ "type" => "presence" }] }
  end
  let(:student) { create(:entity, customer: customer, name: "Student", property_schema: [name_attribute].to_json) }

  def form(launched:, fields: [{ "id" => "f1", "property_slug" => "name", "property_type" => "string", "source" => "entity" }],
           built: nil, process: true)
    config = { "pages" => [{ "id" => "p1", "fields" => fields }] }
    page = build(:page, customer: customer, entity: student, launched: launched, configuration: config.to_json)
    page.save!(validate: false)
    page.update_column(:entity_version_id, built.id) if built
    bind_page_flowchart(page) if process
    Page.find(page.id)
  end

  # The form collects only Name, so a required Motto blocks every submission.
  def require_motto
    student.property_schema_json = [name_attribute, motto_attribute]
    student.save!(validate: false)
  end

  def move_student_forward
    student.property_schema_json = student.property_schema_json + [name_attribute.merge("name" => "Email", "name_slug" => "email")]
    student.save!(validate: false)
  end

  def blocked = [I18n.t("maint_core.errors.page_launch.required_field_missing", field: "Motto", audience: I18n.t("common.visibility.admin"))]
  def process_message(key, **vars) = I18n.t("maint_core.errors.page_launch.#{key}", **vars)

  it "flags a launched form with blockers ahead of being out of date" do
    require_motto
    page = form(launched: true, built: Entity.find(student.id).current_version)
    move_student_forward

    status = described_class.for([page])[page.id]

    expect(status).to have_attributes(kind: :cannot_submit, problems: blocked)
  end

  it "flags a launched form whose bound process is missing or offline" do
    missing = form(launched: true, process: false)
    missing.update_column(:flowchart_id, nil)

    offline = form(launched: true, process: false)
    offline.update_column(:flowchart_id, create(:flowchart, :draft, customer: customer).id)

    statuses = described_class.for([missing.reload, offline.reload])
    expect(statuses[missing.id]).to have_attributes(
      kind: :cannot_submit, problems: [process_message(:submission_process_missing)]
    )
    expect(statuses[offline.id]).to have_attributes(
      kind: :cannot_submit, problems: [process_message(:submission_process_offline)]
    )
  end

  it "flags a launched form whose bound process no longer fits its entity" do
    page = form(launched: true, process: false)
    bind_page_flowchart(page, steps: [{
      "action" => "set_record_fields",
      "config" => { "assignments" => [{ "key" => "removed_field", "value" => "1" }] }
    }])

    expect(described_class.for([page.reload])[page.id]).to have_attributes(
      kind: :cannot_submit, problems: [process_message(:submission_process_incompatible, entity: student.display_label)]
    )
  end

  it "checks each flowchart against each entity once for a whole list" do
    pages = Array.new(3) { form(launched: true) }
    shared = pages.first.flowchart
    pages.drop(1).each { |page| page.update_column(:flowchart_id, shared.id) }
    allow(Flowcharts::Compatibility).to receive(:errors).and_call_original

    described_class.for(pages.map(&:reload))

    expect(Flowcharts::Compatibility).to have_received(:errors).once
  end

  it "flags an out-of-date form, including an offline one with blockers" do
    require_motto
    built = Entity.find(student.id).current_version
    page = form(launched: false, built: built)
    move_student_forward
    current = Entity.find(student.id).resolved_current_version

    expect(described_class.for([page])[page.id]).to have_attributes(
      kind: :out_of_date, problems: [], built: built.version_number, current: current.version_number, entity_name: "Student"
    )
  end

  it "needs no badge for a healthy, current or hand-built form" do
    current = form(launched: true, built: student.current_version)
    hand_built = form(launched: true)

    expect(described_class.for([current, hand_built])).to eq(current.id => nil, hand_built.id => nil)
  end

  it "reads each entity once for the whole list" do
    require_motto
    # Active pages are unique on (customer_id, entity_version_id), so each
    # generated form needs its own version of the same entity.
    pages = Array.new(3) do |i|
      student.property_schema_json = [name_attribute.merge("name" => "Name #{i}"), motto_attribute]
      student.save!(validate: false)
      form(launched: true, built: Entity.find(student.id).current_version, process: false)
    end
    count = ->(list) do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { described_class.for(list) }
      queries
    end

    expect(count.call(pages)).to eq(count.call(pages.first(1)))
  end
end
