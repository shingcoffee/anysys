# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::AssociationSectionComponent, type: :component do
  let(:customer) { create(:customer) }

  include_context "student course association"

  let(:section) { Entities::EntryAssociations.new(entity: student_entity, customer: customer).sections(student).sole }

  def render_section(writable: true, journey: nil)
    render_inline(described_class.new(section: section, entity: student_entity, entry: student,
                                      customer_id: customer.id, writable: writable, journey: journey))
  end

  it "names its anchor after the bridge entity" do
    expect(described_class.section_id(section.association)).to eq("entry-association-#{bridge_entity.id}")
  end

  it "renders desktop rows and mobile cards with the linked record first and blanks as em dashes" do
    enroll(student, math, status: "enrolled", grade: "")

    render_section

    math_path = "/#{customer.id}/admin/entities/#{course_entity.id}/entries/#{math.id}"
    aggregate_failures do
      expect(page).to have_css("section#entry-association-#{bridge_entity.id} h2", text: "Course")
      expect(page).to have_css("table tbody td a[href='#{math_path}']", text: "MATH-101")
      expect(page).to have_css("table tbody td span.line-clamp-3", text: I18n.t("common.labels.em_dash"))
      expect(page).to have_css("ul.sm\\:hidden li a[href='#{math_path}']", text: "MATH-101")
      expect(page).to have_css("ul.sm\\:hidden dt", text: "Grade")
      expect(page).to have_text(I18n.t("admin_misc.entities.association_entries.entry_count", count: 1))
    end
  end

  it "does not link a record that is gone" do
    enroll(student, physics, status: "enrolled")
    physics.delete

    render_section

    expect(page).to have_text(I18n.t("common.references.missing", id: physics.id))
    expect(page).not_to have_css("a[href$='/entities/#{course_entity.id}/entries/#{physics.id}']")
  end

  it "opens add and edit in the dialog without Turbo prefetching their full pages" do
    enroll(student, math, status: "enrolled")

    render_section

    dialog_links = page.all("a[data-action='association-dialog#open']")
    aggregate_failures do
      expect(dialog_links.map { |link| link[:href] }).to include(a_string_ending_with("/new"), a_string_ending_with("/edit"))
      expect(dialog_links.map { |link| link["data-turbo-prefetch"] }.uniq).to eq(["false"])
    end
  end

  it "hides add, edit and delete when not writable" do
    enroll(student, math, status: "enrolled")

    render_section(writable: false)

    expect(page).not_to have_css("a[href$='/new']")
    expect(page).not_to have_css("a[data-turbo-method='delete']")
    expect(page).not_to have_css("th .sr-only")
  end

  it "renders the empty state, with the add hint only when writable" do
    render_section
    expect(page).to have_text(I18n.t("admin_misc.entities.association_entries.empty_title", name: "Course"))
    expect(page).to have_text(I18n.t("admin_misc.entities.association_entries.empty_hint", name: "Course"))

    render_section(writable: false)
    expect(page).not_to have_text(I18n.t("admin_misc.entities.association_entries.empty_hint", name: "Course"))
  end

  describe "with a journey that adds these rows" do
    let(:journey) { create(:journey, customer: customer, key: "student_courses", name: "Add courses") }
    let(:start_path) { "/#{customer.id}/admin/entities/#{student_entity.id}/entries/#{student.id}/journeys/student_courses" }

    it "starts the journey from Add instead of opening the dialog" do
      render_section(journey: journey)

      button = page.find("form[action='#{start_path}'][method='post'] button[type='submit'][data-journey-start='student_courses']")
      expect(button[:title]).to eq(I18n.t("journeys.runtime.start_from_record", name: "Add courses"))
      expect(button["data-section-scroll-target"]).to eq("cue")
      expect(button).to have_text(I18n.t("admin_misc.entities.association_entries.add"))
      expect(page).not_to have_css("a[href$='/new']")
    end

    it "offers neither when not writable" do
      render_section(writable: false, journey: journey)

      expect(page).not_to have_css("[data-journey-start]")
      expect(page).not_to have_css("a[href$='/new']")
    end
  end
end
