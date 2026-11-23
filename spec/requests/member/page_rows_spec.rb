# frozen_string_literal: true

require "rails_helper"

# A member manages the lines of their own order from its member page: the
# lines' member page (generated for the member journey) is set to manage
# them, so the order's page lists them with Add, Change and Remove.
RSpec.describe "Member managing the rows of their own record", type: :request do
  let(:customer) { create(:customer) }
  let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
  let(:member) { create(:user, :member, customer: customer) }
  let(:other_member) { create(:user, :member, customer: customer) }

  let(:student_entity) do
    create(:entity, customer: customer, name: "Student", display_label: "Student", extended_model: person_model,
                    property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
  end
  let(:course_entity) do
    create(:entity, customer: customer, name: "Course", display_label: "Course",
                    property_schema: [{ "name" => "Code", "name_slug" => "code", "html_type" => "text" }].to_json)
  end
  let(:order_entity) do
    create(:entity, customer: customer, name: "Order", display_label: "Order", property_schema: [
      { "name" => "Student", "name_slug" => "student", "html_type" => "select", "type" => "EntityReference",
        "entity_id" => student_entity.id.to_s, "validators" => [{ "type" => "presence" }] },
      { "name" => "Number", "name_slug" => "number", "html_type" => "text" }
    ].to_json)
  end
  let(:line_entity) { Entity.find_by!(customer_id: customer.id, name: "assoc_order_course") }

  before { enable_module!("authentication", customer).set_extendable_model!(person_model, true) }

  let!(:own_student) { create(:entity_entry, entity: student_entity, customer: customer, user: member) }
  let!(:peer_student) { create(:entity_entry, entity: student_entity, customer: customer, user: other_member) }
  let!(:math) { create(:entity_entry, :with_data, customer: customer, entity: course_entity, entry_data: { "code" => "MATH-101" }) }
  let!(:journey) do
    order_entity.associations_json = [{ "target_entity_id" => course_entity.id, "target_entity_name" => course_entity.name,
                                        "display_field" => "code", "display_field_label" => "Code",
                                        "additional_attributes" => [{ "name" => "Quantity", "name_slug" => "quantity",
                                                                      "html_type" => "number" }] }]
    order_entity.save!
    order_entity.sync_bridge_entities!
    domain = create(:entity_domain, customer: customer, name: "Shop")
    [student_entity, course_entity, order_entity.reload].each { |entity| EntityDomains::Memberships.place!(entity, domain) }
    Journeys::Activities::Generate.call(customer: customer, domain_id: domain.id, candidate_key: "member-#{order_entity.id}").journey
  end
  let!(:own_order) { order_row(own_student, "A-1") }
  let!(:peer_order) { order_row(peer_student, "P-1") }
  let!(:own_line) { line_row(own_order, 2) }
  let!(:peer_line) { line_row(peer_order, 5) }

  def order_row(student, number)
    create(:entity_entry, :with_data, customer: customer, entity: order_entity, entry_data: { "student" => student.id.to_s, "number" => number })
  end

  def line_row(order, quantity)
    create(:entity_entry, :with_data, customer: customer, entity: line_entity,
                                      entry_data: { "order" => order.id.to_s, "course" => math.id.to_s, "quantity" => quantity })
  end

  def line_page = Page.find_by!(customer_id: customer.id, action_key: "member_order_add_course")
  def order_path(order) = member_surface_path(customer.id, "entity_#{order_entity.id}", order.id)
  def submit_path = "/#{customer.id}/page/#{line_page.public_uuid}"
  def lines = EntityEntry.where(customer_id: customer.id, entity_id: line_entity.id)

  def manage_rows!(modes: %w[create update])
    page = line_page
    config = page.configuration_json
    page.configuration_json = config.merge("form_settings" => config["form_settings"].merge("modes" => modes, "manage_rows" => true))
    page.save!
  end

  def run_token = Addressable::URI.parse(response.location).query_values["run"]

  before { sign_in member }

  it "lists the record's rows read-only while no page manages them, and never another member's" do
    get order_path(own_order)

    section = Nokogiri::HTML(response.body).at_css("[data-record-rows='#{line_entity.id}']")
    expect(section.at_css("h2").text.strip).to eq("Course")
    expect(section.text).to include("MATH-101", "2")
    expect(section.text).not_to include("5")
    expect(section.text).not_to include(I18n.t("member.record_rows.change"), I18n.t("member.record_rows.remove"))
    expect(section.text).not_to include(I18n.t("member.record_rows.add"))

    get new_member_page_row_path(customer.id, line_page, record: own_order.id)
    expect(response).to have_http_status(:not_found)
  end

  context "when the rows' page manages them" do
    before { manage_rows! }

    it "offers Add, Change and Remove on the record's page" do
      get order_path(own_order)

      section = Nokogiri::HTML(response.body).at_css("[data-record-rows='#{line_entity.id}']")
      expect(section.at_css("a[href='#{new_member_page_row_path(customer.id, line_page, record: own_order.id)}']")).to be_present
      expect(section.at_css("a[href='#{edit_member_page_row_path(customer.id, line_page, own_line)}']")).to be_present
      expect(section.at_css("form[action='#{member_page_row_path(customer.id, line_page, own_line)}']")).to be_present
    end

    it "adds a row to the member's record and returns to it" do
      get new_member_page_row_path(customer.id, line_page, record: own_order.id)
      token = run_token
      expect(response.location).to include(member_page_path(customer.id, line_page))

      follow_redirect!
      body = Nokogiri::HTML(response.body)
      expect(body.at_css("[data-role='locked-inputs']").text).to include("A-1")
      expect(body.at_css("[name='entity[order]']")).to be_nil

      expect { post submit_path, params: { _run: token, entity: { course: math.id.to_s, quantity: "4" } } }.to change(lines, :count).by(1)
      expect(lines.order(:id).last.data_json).to include("order" => own_order.id.to_s, "quantity" => "4")
      expect(response).to redirect_to(order_path(own_order))
    end

    it "changes a row of the member's record and returns to it" do
      get edit_member_page_row_path(customer.id, line_page, own_line)
      token = run_token
      expect(Addressable::URI.parse(response.location).query_values["entry"]).to eq(own_line.id.to_s)

      follow_redirect!
      expect(Nokogiri::HTML(response.body).at_css("[name='entity[quantity]']")["value"]).to eq("2")

      post "#{submit_path}?entry_id=#{own_line.id}", params: { _run: token, entity: { course: math.id.to_s, quantity: "7" } }
      expect(own_line.reload.data_json).to include("order" => own_order.id.to_s, "quantity" => "7")
      expect(lines.count).to eq(2)
      expect(response).to redirect_to(order_path(own_order))
    end

    it "removes a row of the member's record" do
      expect { delete member_page_row_path(customer.id, line_page, own_line) }.to change(lines, :count).by(-1)
      expect(response).to redirect_to(order_path(own_order))
      expect(flash[:notice]).to eq(I18n.t("member.record_rows.removed"))
    end

    it "never adds to, changes or removes from another member's record" do
      get order_path(own_order)
      get order_path(peer_order)
      expect(response).to have_http_status(:not_found)
      get new_member_page_row_path(customer.id, line_page, record: peer_order.id)
      expect(response).to have_http_status(:not_found)
      get edit_member_page_row_path(customer.id, line_page, peer_line)
      expect(response).to have_http_status(:not_found)
      get member_page_path(customer.id, line_page, entry: peer_line.id)
      expect(response).to have_http_status(:not_found)
      expect { delete member_page_row_path(customer.id, line_page, peer_line) }.not_to change(lines, :count)
      expect(response).to have_http_status(:not_found)

      post "#{submit_path}?entry_id=#{peer_line.id}", params: { entity: { course: math.id.to_s, quantity: "9" } }
      expect(peer_line.reload.data_json["quantity"]).to eq(5)
    end

    it "offers no Change on a page that only adds rows" do
      manage_rows!(modes: %w[create])

      get order_path(own_order)
      section = Nokogiri::HTML(response.body).at_css("[data-record-rows='#{line_entity.id}']")
      expect(section.text).not_to include(I18n.t("member.record_rows.change"))
      expect(section.text).to include(I18n.t("member.record_rows.remove"))

      get edit_member_page_row_path(customer.id, line_page, own_line)
      expect(response).to have_http_status(:not_found)
    end

    it "is for members only" do
      sign_in create(:user, :admin, customer: customer)

      expect { delete member_page_row_path(customer.id, line_page, own_line) }.not_to change(lines, :count)
      expect(response).to redirect_to("/#{customer.id}/admin/assistant")
    end
  end
end
