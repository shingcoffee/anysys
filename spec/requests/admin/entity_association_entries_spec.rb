# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin entry association entries", type: :request do
  include_context "as admin"
  include_context "student course association"

  let(:detail_path) { admin_entity_entry_path(customer.id, student_entity, student) }
  let(:section_id) { "entry-association-#{bridge_entity.id}" }
  let(:new_path) { new_admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id) }
  let(:create_path) { admin_entity_entry_association_entries_path(customer.id, student_entity, student, bridge_entity.id) }
  let(:rows) { { "0" => { course: math.id.to_s, status: "enrolled", grade: "91" }, "1" => { course: physics.id.to_s, status: "dropped", grade: "" } } }

  def html = Nokogiri::HTML(response.body)
  def bridge_rows = EntityEntry.where(entity_id: bridge_entity.id).order(:id)

  describe "entry detail page" do
    it "renders one section per association with linked rows, reference links and row actions" do
      enrollment = enroll(student, math, status: "enrolled", grade: "88", secret: "hidden")
      enroll(create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: { "full_name" => "Bo" }), physics)

      get detail_path

      section = html.at_css("section##{section_id}")
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(section.at_css("h3").text.strip).to eq("Course")
        expect(section.css("thead th").map { |th| th.text.strip }).to eq(["Course", "Status", "Grade", I18n.t("common.labels.actions")])
        cells = section.css("tbody tr").map { |tr| tr.css("td").first(3).map { |td| td.text.strip } }
        expect(cells).to eq([%w[MATH-101 Enrolled 88]])
        expect(section.at_css("tbody a[href='#{admin_entity_entry_path(customer.id, course_entity.id, math)}']")).to be_present
        expect(section.text).not_to include("hidden")
        expect(section.at_css("a[href='#{new_path}']")).to be_present
        edit = edit_admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment)
        expect(section.at_css("tbody a[href='#{edit}']")).to be_present
        destroy = section.at_css("tbody a[href='#{admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment)}']")
        expect(destroy["data-turbo-method"]).to eq("delete")
        expect(html.at_css("nav a[href='##{section_id}']")).to be_present
      end
    end

    it "shows the empty state with Add" do
      get detail_path

      expect(html.at_css("section##{section_id}").text).to include(I18n.t("admin_misc.entities.association_entries.empty_title", name: "Course"))
      expect(html.at_css("section##{section_id} a[href='#{new_path}']")).to be_present
    end

    it "shows the association from the associated entity's entries, listing the records linked to that entry" do
      enroll(student, math, status: "enrolled", grade: "91")
      enroll(student, physics, status: "dropped")

      get admin_entity_entry_path(customer.id, course_entity, math)

      section = html.at_css("section##{section_id}")
      expect(section.at_css("h3").text).to eq("Student")
      expect(section.css("tbody tr").size).to eq(1)
      expect(section.at_css("tbody a")["href"]).to eq(admin_entity_entry_path(customer.id, student_entity, student))
      expect(section.at_css("tbody a").text).to eq("Ada")
      expect(section.at_css("a[data-action='association-dialog#open']")["href"])
        .to eq(new_admin_entity_entry_association_entry_path(customer.id, course_entity, math, bridge_entity.id))
    end
  end

  describe "authorization and record boundary" do
    let(:guard_path) { new_path }

    it_behaves_like "an admin-guarded GET"

    context "on POST" do
      let(:guard_path) { create_path }

      it_behaves_like "an admin-guarded request", :post
    end

    it "never lets a member write" do
      sign_in create(:user, :member, customer: customer)

      expect { post create_path, params: { rows: rows } }.not_to change(EntityEntry, :count)
    end

    it "keeps a foreign admin out" do
      sign_in create(:user, :admin, customer: create(:customer))

      expect { post create_path, params: { rows: rows } }.not_to change(EntityEntry, :count)
    end

    it "returns 404 for another tenant's entry" do
      foreign = create(:entity_entry, :with_data, entity: create(:entity), entry_data: {})

      get new_admin_entity_entry_association_entry_path(customer.id, student_entity, foreign, bridge_entity.id)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a bridge the entity does not declare" do
      other_bridge = create(:entity, customer: customer, category: :bridge, property_schema: [].to_json)

      get new_admin_entity_entry_association_entry_path(customer.id, student_entity, student, other_bridge.id)

      expect(response).to have_http_status(:not_found)
    end

    describe "from the associated entity's entry" do
      let(:course_create_path) { admin_entity_entry_association_entries_path(customer.id, course_entity, math, bridge_entity.id) }

      it "offers the declaring entity's records as a picker in the add form" do
        get new_admin_entity_entry_association_entry_path(customer.id, course_entity, math, bridge_entity.id)

        expect(response).to have_http_status(:ok)
        picker = html.at_css("select[name='rows[0][student]']")
        expect(picker.css("option").map { |option| [option.text, option["value"]] }).to include(["Ada", student.id.to_s])
        expect(html.at_css("[name='rows[0][course]']")).to be_nil
      end

      it "adds rows linking the chosen records to this entry" do
        post course_create_path, params: { rows: { "0" => { student: student.id.to_s, status: "enrolled", grade: "88" } } }

        expect(response).to redirect_to(admin_entity_entry_path(customer.id, course_entity, math, anchor: section_id))
        expect(bridge_rows.sole.data_json).to include("student" => student.id.to_s, "course" => math.id.to_s, "grade" => "88")
      end

      it "rejects a record of another tenant or another entity as the linked participant" do
        foreign = create(:entity_entry, :with_data, customer: create(:customer), entity: student_entity, entry_data: {})

        [foreign.id, physics.id].each do |id|
          post course_create_path, params: { rows: { "0" => { student: id.to_s, status: "enrolled" } } }

          expect(response).to have_http_status(:unprocessable_entity)
        end
        expect(bridge_rows).to be_empty
      end
    end

    context "with a bridge row that belongs to another student" do
      let(:theirs) { enroll(create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: {}), math, status: "enrolled") }

      it "returns 404 on edit" do
        get edit_admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, theirs)

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 on delete and keeps the row" do
        delete admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, theirs)

        expect(response).to have_http_status(:not_found)
        expect(theirs.reload).to be_present
      end
    end

    it "rejects a rows payload that is not an object with 400" do
      post create_path, params: { rows: "scalar" }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET new" do
    it "renders one row with the target dropdown and bridge fields, but not the fixed or hidden references" do
      get new_path

      form = html.at_css("form[action='#{create_path}']")
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(html.at_css("h1").text.strip).to eq(I18n.t("admin_misc.entities.association_entries.new_title", name: "Course"))
        expect(form.css("ol > li")).to have_attribute_rows(1)
        options = form.css("select[name='rows[0][course]'] option").map { |option| option.text.strip }
        expect(options).to include("MATH-101", "PHYS-201")
        expect(form.at_css("select[name='rows[0][status]'] option[selected]")["value"]).to eq("enrolled")
        expect(form.at_css("input[name='rows[0][grade]']")).to be_present
        expect(form.at_css("[name='rows[0][student]']")).to be_nil
        expect(form.at_css("[name='rows[0][secret]']")).to be_nil
        expect(form.at_css("template [name='rows[__ROW__][course]']")).to be_present
      end
    end
  end

  describe "POST create" do
    it "adds every submitted row linked to the entry and redirects to its section" do
      expect { post create_path, params: { rows: rows } }.to change(EntityEntry, :count).by(2)

      expect(response).to redirect_to("#{detail_path}##{section_id}")
      expect(flash[:notice]).to eq(I18n.t("admin_misc.entities.association_entries.created", count: 2))
      expect(bridge_rows.map(&:data_json)).to eq([
        { "course" => math.id.to_s, "status" => "enrolled", "grade" => "91", "student" => student.id.to_s },
        { "course" => physics.id.to_s, "status" => "dropped", "grade" => "", "student" => student.id.to_s }
      ])
      expect(bridge_rows.map(&:customer_id).uniq).to eq([customer.id])
    end

    it "ignores a forged reference back to another entry" do
      other = create(:entity_entry, :with_data, customer: customer, entity: student_entity, entry_data: {})

      post create_path, params: { rows: { "0" => { course: math.id.to_s, status: "enrolled", student: other.id.to_s } } }

      expect(bridge_rows.last.data_json["student"]).to eq(student.id.to_s)
    end

    it "saves nothing and rerenders every row's errors when any row is invalid" do
      foreign_course = create(:entity_entry, :with_data, entity: create(:entity), entry_data: {})
      params = { rows: { "0" => { course: math.id.to_s, status: "enrolled", grade: "101" },
                         "1" => { course: "", status: "enrolled" },
                         "5" => { course: foreign_course.id.to_s, status: "enrolled" } } }

      expect { post create_path, params: params }.not_to change(EntityEntry, :count)

      aggregate_failures do
        expect(response).to have_http_status(:unprocessable_entity)
        form = html.at_css("form[action='#{create_path}']")
        expect(form.at_css("[role='alert']")).to be_present
        expect(form.css("ol > li")).to have_attribute_rows(3)
        expect(form.at_css("input[name='rows[0][grade]']")["value"]).to eq("101")
        expect(form.at_css("#association_row_0_grade_errors")).to be_present
        expect(form.at_css("#association_row_1_course_errors")).to be_present
        expect(form.css("ol > li")[2].text).to include(I18n.t("common.errors.dynamic.association_target_missing", field: "Course"))
        expect(form.at_css("[data-association-rows-next-index-value='3']")).to be_present
      end
    end
  end

  describe "edit, update and destroy" do
    let!(:enrollment) { enroll(student, math, status: "enrolled", grade: "70", secret: "kept") }
    let(:edit_path) { edit_admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment) }
    let(:row_path) { admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment) }

    it "edits the grade in place and keeps the hidden and fixed values" do
      get edit_path
      expect(html.at_css("form[action='#{row_path}'] input[name='entry[data][grade]']")["value"]).to eq("70")

      patch row_path, params: { entry: { data: { course: physics.id.to_s, status: "enrolled", grade: "95", student: "0" } } }

      expect(response).to redirect_to("#{detail_path}##{section_id}")
      expect(flash[:notice]).to eq(I18n.t("admin_misc.entities.association_entries.updated"))
      expect(enrollment.reload.data_json).to eq("student" => student.id.to_s, "course" => physics.id.to_s,
                                                "status" => "enrolled", "grade" => "95", "secret" => "kept")
    end

    it "rerenders an invalid edit with 422 without writing" do
      patch row_path, params: { entry: { data: { grade: "-5" } } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(enrollment.reload.data_json["grade"]).to eq("70")
    end

    it "deletes the row and returns to the section" do
      expect { delete row_path }.to change(EntityEntry, :count).by(-1)

      expect(response).to redirect_to("#{detail_path}##{section_id}")
      expect(flash[:notice]).to eq(I18n.t("admin_misc.entities.association_entries.deleted"))
      expect(student.reload).to be_present
    end

    it "returns a same-tenant user page after delete" do
      account = create(:user, :member, customer: customer)
      return_to = admin_modules_authentication_user_path(customer.id, account, anchor: "user-#{account.id}-association")

      delete row_path, params: { return_to: return_to }

      expect(response).to redirect_to(return_to)
      expect(EntityEntry.where(id: enrollment.id)).to be_empty
    end

    it "ignores an off-site return path and comes back to the entry section" do
      delete row_path, params: { return_to: "https://evil.example/phish" }

      expect(response).to redirect_to("#{detail_path}##{section_id}")
    end

    it "keeps a same-tenant return path on the full edit form and follows it after update" do
      account = create(:user, :member, customer: customer)
      return_to = admin_modules_authentication_user_path(customer.id, account, anchor: "course-section")

      get edit_path, params: { return_to: return_to }

      form = html.at_css("form[action*='/associations/']")
      query = Rack::Utils.parse_query(URI.parse(form["action"]).query)
      expect(query["return_to"]).to eq(return_to)
      expect(form.at_css("a[href='#{return_to}']")).to be_present

      patch row_path, params: { return_to: return_to, entry: { data: { grade: "95" } } }

      expect(response).to redirect_to(return_to)
      expect(enrollment.reload.data_json["grade"]).to eq("95")
    end
  end

  describe "in the entry page dialog" do
    let(:frame) { { "Turbo-Frame" => "entity-quick-add-frame-0" } }
    let!(:enrollment) { enroll(student, math, status: "enrolled", grade: "70") }
    let(:row_path) { admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment) }

    it "wires the detail page's Add and Edit links to the dialog it renders" do
      get detail_path

      section = html.at_css("section##{section_id}")
      expect(section["data-controller"]).to eq("association-dialog")
      expect(section["data-association-dialog-entity-quick-add-dialog-outlet"]).to eq("#entity-quick-add-dialog-0")
      add = section.at_css("a[href='#{new_path}']")
      expect(add["data-action"]).to eq("association-dialog#open")
      expect(add["data-association-dialog-title-param"]).to eq(I18n.t("admin_misc.entities.association_entries.new_title", name: "Course"))
      expect(html.css("dialog#entity-quick-add-dialog-0").size).to eq(1)
    end

    it "renders the Add form alone in the dialog frame, submitting into it, with nested quick-add at the next level" do
      get new_path, headers: frame

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(html.at_css("html head")).to be_nil
        form = html.at_css("turbo-frame#entity-quick-add-frame-0 form[action='#{create_path}']")
        expect(form["data-turbo-frame"]).to be_nil
        expect(form.at_css("button[data-action='entity-quick-add-dialog#close']")).to be_present
        expect(form.at_css("select[name='rows[0][course]']").ancestors("[data-controller='entity-quick-add']").first["data-entity-quick-add-entity-quick-add-dialog-outlet"])
          .to eq("#entity-quick-add-dialog-1")
        expect(html.at_css("dialog#entity-quick-add-dialog-1")).to be_present
      end
    end

    it "answers a saved Add with the dialog's saved marker and keeps the notice for the reload" do
      expect { post create_path, params: { rows: rows }, headers: frame }.to change(EntityEntry, :count).by(2)

      marker = html.at_css("turbo-frame#entity-quick-add-frame-0 [data-entity-quick-add-dialog-target='created']")
      expect(response).to have_http_status(:ok)
      expect(marker.text.strip).to eq(I18n.t("admin_misc.entities.association_entries.created", count: 2))
      expect(flash[:notice]).to eq(I18n.t("admin_misc.entities.association_entries.created", count: 2))
    end

    it "rerenders an invalid Add inside the frame with 422" do
      post create_path, params: { rows: { "0" => { course: "", status: "enrolled" } } }, headers: frame

      expect(response).to have_http_status(:unprocessable_entity)
      expect(html.at_css("turbo-frame#entity-quick-add-frame-0 [role='alert']")).to be_present
      expect(html.at_css("[data-entity-quick-add-dialog-target='created']")).to be_nil
    end

    it "edits in the frame and answers with the saved marker" do
      get edit_admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment), headers: frame
      expect(html.at_css("turbo-frame#entity-quick-add-frame-0 form[action='#{row_path}'] input[name='entry[data][grade]']")["value"]).to eq("70")
      expect(html.at_css("form button[data-action='entity-quick-add-dialog#close']")).to be_present

      patch row_path, params: { entry: { data: { grade: "85" } } }, headers: frame

      expect(html.at_css("[data-entity-quick-add-dialog-target='created']").text.strip).to eq(I18n.t("admin_misc.entities.association_entries.updated"))
      expect(enrollment.reload.data_json["grade"]).to eq("85")
    end

    it "rerenders an invalid edit inside the frame with 422" do
      patch row_path, params: { entry: { data: { grade: "-1" } } }, headers: frame

      expect(response).to have_http_status(:unprocessable_entity)
      expect(html.at_css("turbo-frame#entity-quick-add-frame-0 form[action='#{row_path}']")).to be_present
    end
  end

  describe "with a launched page that saves the links" do
    let(:frame) { { "Turbo-Frame" => "entity-quick-add-frame-0" } }
    let(:modes) { %w[create update] }
    let(:inputs) { [{ field: "student", entity_id: student_entity.id }] }
    let(:audiences) { {} }
    let!(:link_page) do
      journey_page(bridge_entity, action_key: "student_courses", name: "Enrol in a course", **audiences,
                                  fields: [journey_reference_field("student", student_entity, "full_name"),
                                           journey_reference_field("course", course_entity, "code"), journey_text_field("status")],
                                  form_settings: { modes: modes, inputs: inputs })
    end

    def frame_node = html.at_css("turbo-frame#entity-quick-add-frame-0")
    def run_for(token) = JourneyRun.find_by(token_digest: JourneyRun.digest_for(token))

    # Follows the hand-over into the page and returns [submit action, run token].
    def open_link_page(path, landing)
      get path, headers: frame
      expect(response).to have_http_status(:see_other)
      location = Addressable::URI.parse(response.location)
      expect(location.path).to eq(landing)
      expect(location.query_values["page"]).to eq(link_page.id.to_s)
      token = location.query_values["run"]
      expect(run_for(token)).to have_attributes(journey_id: nil, user_id: admin.id)
      expect(run_for(token).bindings_for(link_page)).to eq("student" => student.id.to_s)

      get response.location, headers: frame
      expect(response).to have_http_status(:ok)
      expect(frame_node.at_css("[data-role='locked-inputs']").text).to include("Ada")
      expect(frame_node.at_css("select[name='entity[student]']")).to be_nil
      form = frame_node.at_css("form")
      expect(form.at_css("input[name='_run']")["value"]).to eq(token)
      [form["action"], token]
    end

    before { allow(Pages::Submit).to receive(:call).and_call_original }

    it "hands Add to the page with the student locked in, so the save runs its flowchart" do
      action, token = open_link_page(new_path, new_admin_entity_entry_path(customer.id, bridge_entity))
      expect(frame_node.at_css("button[data-action='entity-quick-add-dialog#close']")).to be_present

      expect { post action, params: { _run: token, entity: { course: math.id.to_s, status: "enrolled" } }, headers: frame }
        .to change(bridge_rows, :count).by(1)
      expect(Pages::Submit).to have_received(:call).with(hash_including(page: link_page))
      row = bridge_rows.last
      expect(row.data_json.slice("student", "course").transform_values(&:to_s)).to eq("student" => student.id.to_s, "course" => math.id.to_s)
      expect(response).to redirect_to(admin_entity_entry_path(customer.id, bridge_entity, row))

      get response.location, headers: frame
      expect(frame_node.at_css("[data-entity-quick-add-dialog-target='created']").text.strip).to eq(I18n.t("admin_misc.entities.entry_form.created"))
      get detail_path
      expect(response.body).to include(I18n.t("admin_misc.entities.entry_form.created"))
    end

    it "keeps the student locked when a submit is refused and retried" do
      action, token = open_link_page(new_path, new_admin_entity_entry_path(customer.id, bridge_entity))

      expect { post action, params: { _run: token, entity: { course: "", status: "enrolled" } }, headers: frame }.not_to change(bridge_rows, :count)
      expect(Addressable::URI.parse(response.location).query_values).to include("run" => token, "page" => link_page.id.to_s)
      get response.location, headers: frame
      expect(frame_node.at_css("[data-role='locked-inputs']").text).to include("Ada")
    end

    it "hands Edit to a page that serves updates, saving the row through it" do
      enrollment = enroll(student, math, status: "enrolled")
      edit_path = edit_admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment)
      action, token = open_link_page(edit_path, edit_admin_entity_entry_path(customer.id, bridge_entity, enrollment))
      expect(frame_node.at_css("button[type='submit']").text).to include(I18n.t("admin_misc.entities.entry_form.update"))

      post action, params: { _run: token, entity: { course: physics.id.to_s, status: "dropped" } }, headers: frame

      expect(Pages::Submit).to have_received(:call).with(hash_including(page: link_page))
      expect(enrollment.reload.data_json.slice("student", "course", "status").transform_values(&:to_s))
        .to eq("student" => student.id.to_s, "course" => physics.id.to_s, "status" => "dropped")
      expect(response).to redirect_to(admin_entity_entry_path(customer.id, bridge_entity, enrollment))
      get response.location, headers: frame
      expect(frame_node.at_css("[data-entity-quick-add-dialog-target='created']").text.strip).to eq(I18n.t("admin_misc.entities.entry_form.updated"))
    end

    it "hands over outside the dialog too" do
      get new_path

      expect(response).to have_http_status(:see_other)
      expect(Addressable::URI.parse(response.location).path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
    end

    context "when the page only adds links" do
      let(:modes) { %w[create] }

      it "keeps today's edit form" do
        enrollment = enroll(student, math, status: "enrolled")
        get edit_admin_entity_entry_association_entry_path(customer.id, student_entity, student, bridge_entity.id, enrollment), headers: frame

        expect(response).to have_http_status(:ok)
        expect(frame_node.at_css("input[name='entry[data][grade]']")).to be_present
      end
    end

    context "when the page does not lock the student" do
      let(:inputs) { [] }

      it "keeps today's multi-row form" do
        get new_path, headers: frame

        expect(response).to have_http_status(:ok)
        expect(frame_node.at_css("form[action='#{create_path}']")).to be_present
      end
    end

    context "when the page is not launched for admins" do
      let(:audiences) { { audience_admin: false, audience_member: true } }

      it "keeps today's multi-row form" do
        get new_path, headers: frame

        expect(response).to have_http_status(:ok)
        expect(frame_node.at_css("form[action='#{create_path}']")).to be_present
      end
    end

    it "does not open a link row's page without the page, outside a record page" do
      enrollment = enroll(student, math, status: "enrolled")

      get edit_admin_entity_entry_path(customer.id, bridge_entity, enrollment), headers: frame
      expect(response).to have_http_status(:not_found)
    end
  end

  matcher :have_attribute_rows do |count|
    match { |nodes| nodes.size == count }
  end
end
