# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member surfaces", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:user)     { create(:user, :member, customer: customer) }

  let(:test_surface) do
    Member::Surface.new(
      key:   :test_widgets,
      label: "Widgets",
      icon:  :sparkles,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title:    "Widgets",
        subtitle: "All widgets",
        scope:    ->(u) { Payments::Payment.where(user_id: u.id, customer_id: u.customer_id).order(:id) },
        columns:  [
          { key: :provider, label: "Provider", value: ->(r) { r.provider } },
          { key: :amount,   label: "Amount",   value: ->(r) { r.amount }, format: :money_major, align: :right }
        ],
        empty_state: { headline: "No widgets", body: "yet", icon: :sparkles },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(r) { "Widget #{r.out_trade_no}" },
        sections: [
          { key: :primary, rows: [
              { key: :provider, label: "Provider", value: ->(r) { r.provider } },
              { key: :amount,   label: "Amount",   value: ->(r) { r.amount }, format: :money_major }
          ]}
        ]
      )
    )
  end

  let(:source_class) do
    surfaces_proc = -> { @stub_surfaces }
    Class.new(Member::SurfaceSource) do
      define_singleton_method(:key)      { :test_widgets_src }
      define_singleton_method(:name)     { "Test"             }
      define_singleton_method(:position) { 99                  }
      define_method(:surfaces) { surfaces_proc.call }
    end
  end

  before do
    enable_module!("authentication", customer, name: "Authentication")

    @stub_surfaces = [test_surface]
    @prior_sources = Member::Surfaces::SourceRegistry.all
    Member::Surfaces::SourceRegistry.register(source_class)

    sign_in user
  end

  after do
    Member::Surfaces::SourceRegistry.reset!
    @prior_sources.each { |s| Member::Surfaces::SourceRegistry.register(s) }
  end

  def make_payment(for_user:)
    order = create(:payment_order,
      customer: customer, external_ref: SecureRandom.hex(4),
      subject: "S", amount: 10.00, currency: "CNY", status: "pending"
    )
    create(:payment,
      customer: customer, user: for_user, payment_order: order,
      provider: "alipay", flow: "qr", out_trade_no: "X-#{SecureRandom.hex(4)}",
      amount: 10.00, status: "succeeded"
    )
  end

  it "returns 404 for an unknown surface key" do
    get "/#{customer.id}/member/totally_unknown"
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for builtin surface keys that are served by dedicated controllers" do
    get "/#{customer.id}/member/builtin_profile"
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for page link surface keys served by Member::PagesController" do
    page = create(:page, :launched, :for_member, customer: customer)
    get "/#{customer.id}/member/page_#{page.id}"
    expect(response).to have_http_status(:not_found)
  end


  it "returns 404 when the surface's enabled_for? returns false" do
    surface = test_surface.dup
    surface.key = :gated_widgets
    surface.enabled_for = ->(_u) { false }
    @stub_surfaces << surface

    get "/#{customer.id}/member/gated_widgets"
    expect(response).to have_http_status(:not_found)
  end

  it "renders the index for a registered surface" do
    make_payment(for_user: user)
    get "/#{customer.id}/member/test_widgets"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Widgets")
    expect(response.body).to include("alipay")
  end

  it "scopes records via the descriptor scope (does not show other users' rows)" do
    other = create(:user, :member, customer: customer)
    make_payment(for_user: other)

    get "/#{customer.id}/member/test_widgets"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No widgets")
  end

  it "returns 404 on show when the record is not in the descriptor scope" do
    other = create(:user, :member, customer: customer)
    theirs = make_payment(for_user: other)

    get "/#{customer.id}/member/test_widgets/#{theirs.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "renders show for a record in the user's scope" do
    mine = make_payment(for_user: user)
    get "/#{customer.id}/member/test_widgets/#{mine.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(mine.out_trade_no)
  end

  describe "admin preview" do
    let(:admin) { create(:user, :admin, customer: customer, first_name: "Ada", last_name: "Admin") }

    before { sign_in admin }

    it "allows a same-tenant admin GET and shows only that admin's own rows" do
      mine = make_payment(for_user: admin)
      theirs = make_payment(for_user: user)

      get "/#{customer.id}/member/test_widgets"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 total")

      get "/#{customer.id}/member/test_widgets/#{mine.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mine.out_trade_no)

      get "/#{customer.id}/member/test_widgets/#{theirs.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "404s show for another user's record even when the admin can preview" do
      theirs = make_payment(for_user: user)

      get "/#{customer.id}/member/test_widgets/#{theirs.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "allows a same-tenant admin HEAD" do
      head "/#{customer.id}/member/test_widgets"
      expect(response).to have_http_status(:ok)
    end

    it "rejects an admin from another tenant" do
      other_admin = create(:user, :admin, customer: create(:customer))
      sign_in other_admin

      get "/#{customer.id}/member/test_widgets"
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(response.status).not_to eq(200)
    end

    it "rejects a same-tenant admin non-GET on a member write route" do
      patch "/#{customer.id}/member/profile",
            params: { member_profiles_update_contract: { first_name: "Hack" } }
      expect(response).to have_http_status(:forbidden).or have_http_status(:found)
      expect(response.status).not_to eq(200)
    end

    it "shows only the admin's own linked person entries on the entity surface" do
      enable_module!("authentication", customer)
        .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      person = create(:entity, customer: customer, name: "PersonSurf",
                               extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
      mine = create(:entity_entry, customer: customer, entity: person, user: admin)
      theirs = create(:entity_entry, customer: customer, entity: person, user: user)
      @stub_surfaces << Member::EntitySurfaceBuilder.call(entity: person, customer: customer)

      get "/#{customer.id}/member/entity_#{person.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 total")

      get "/#{customer.id}/member/entity_#{person.id}/#{mine.id}"
      expect(response).to have_http_status(:ok)

      get "/#{customer.id}/member/entity_#{person.id}/#{theirs.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "rejects admin POST, PATCH, and DELETE on the person surface and on member writes" do
      enable_module!("authentication", customer)
        .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      person = create(:entity, customer: customer, name: "PersonWrite",
                               extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
      mine = create(:entity_entry, customer: customer, entity: person, user: admin)
      @stub_surfaces << Member::EntitySurfaceBuilder.call(entity: person, customer: customer)
      path = "/#{customer.id}/member/entity_#{person.id}"

      post path
      expect(response).to have_http_status(:forbidden).or have_http_status(:found).or have_http_status(:not_found)
      expect(response.status).not_to eq(200)

      patch "#{path}/#{mine.id}"
      expect(response).to have_http_status(:forbidden).or have_http_status(:found).or have_http_status(:not_found)
      expect(response.status).not_to eq(200)

      delete "#{path}/#{mine.id}"
      expect(response).to have_http_status(:forbidden).or have_http_status(:found).or have_http_status(:not_found)
      expect(response.status).not_to eq(200)
    end
  end

  describe "person entity surface for a member" do
    let(:person) do
      enable_module!("authentication", customer)
        .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      create(:entity, customer: customer, name: "PersonMember",
             extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
    end
    let(:other_member) { create(:user, :member, customer: customer) }
    let!(:mine) { create(:entity_entry, customer: customer, entity: person, user: user) }
    let!(:theirs) { create(:entity_entry, customer: customer, entity: person, user: other_member) }
    let!(:unlinked) { create(:entity_entry, customer: customer, entity: person) }

    before { @stub_surfaces << Member::EntitySurfaceBuilder.call(entity: person, customer: customer) }

    it "lists only the member's own linked entries and 404s another member's show" do
      get "/#{customer.id}/member/entity_#{person.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 total")

      get "/#{customer.id}/member/entity_#{person.id}/#{mine.id}"
      expect(response).to have_http_status(:ok)

      get "/#{customer.id}/member/entity_#{person.id}/#{theirs.id}"
      expect(response).to have_http_status(:not_found)

      get "/#{customer.id}/member/entity_#{person.id}/#{unlinked.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "owned enrollment surface" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let(:student) do
      enable_module!("authentication", customer)
        .set_extendable_model!(person_model, true)
      create(:entity, customer: customer, name: "Student", extended_model: person_model,
             property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
    end
    let(:course) do
      create(:entity, customer: customer, name: "CourseSurf",
             property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
    end
    let(:enrollment) do
      student.associations_json = [association_to(course)]
      student.save!
      student.sync_bridge_entities!
      student.reload
      Entity.find(student.associations_list.first.fetch("bridge_entity_id"))
    end
    let(:other_member) { create(:user, :member, customer: customer) }
    let!(:own_student) { create(:entity_entry, customer: customer, entity: student, user: user) }
    let!(:peer_student) { create(:entity_entry, customer: customer, entity: student, user: other_member) }
    let!(:mine) do
      create(:entity_entry, :with_data, customer: customer, entity: enrollment,
             entry_data: { "student" => own_student.id.to_s })
    end
    let!(:theirs) do
      create(:entity_entry, :with_data, customer: customer, entity: enrollment,
             entry_data: { "student" => peer_student.id.to_s })
    end

    before { @stub_surfaces << Member::EntitySurfaceBuilder.call(entity: enrollment, customer: customer) }

    it "404s another member's enrollment detail and another tenant's member" do
      get "/#{customer.id}/member/entity_#{enrollment.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 total")

      get "/#{customer.id}/member/entity_#{enrollment.id}/#{theirs.id}"
      expect(response).to have_http_status(:not_found)

      other_customer = create(:customer)
      foreign = create(:user, :member, customer: other_customer)
      enable_module!("authentication", other_customer)
      sign_in foreign

      get "/#{other_customer.id}/member/entity_#{enrollment.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "opens the member's own enrollment detail with the referenced course's label" do
      algebra = create(:entity_entry, :with_data, customer: customer, entity: course, entry_data: { "title" => "Algebra" })
      mine.update!(data: mine.data_json.merge("coursesurf" => algebra.id.to_s).to_json)

      get "/#{customer.id}/member/entity_#{enrollment.id}/#{mine.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Algebra")
    end

    it "lists only the admin's own enrollments when previewing" do
      admin = create(:user, :admin, customer: customer)
      admin_student = create(:entity_entry, customer: customer, entity: student, user: admin)
      create(:entity_entry, :with_data, customer: customer, entity: enrollment,
             entry_data: { "student" => admin_student.id.to_s })
      sign_in admin

      get "/#{customer.id}/member/entity_#{enrollment.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("1 total")

      get "/#{customer.id}/member/entity_#{enrollment.id}/#{mine.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  def association_to(target)
    {
      "target_entity_id" => target.id,
      "target_entity_name" => target.name,
      "display_field" => "title",
      "display_field_label" => "Title",
      "additional_attributes" => []
    }
  end

  it "batch-primes computed values on an entity-entry index so the page is not N+1" do
    host = create(:entity, name: "StudentSurf", customer: customer)
    klass = create(:entity, name: "ClassSurf", customer: customer)
    bridge = create(:entity, name: "assoc_student_surf_class_surf", customer: customer, category: :bridge,
      property_schema: [
        { "name" => "Student", "name_slug" => "student_surf", "type" => "EntityReference", "entity_id" => host.id.to_s },
        { "name" => "Class", "name_slug" => "class_surf", "type" => "EntityReference", "entity_id" => klass.id.to_s },
        { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
      ].to_json)
    host.property_schema_json = [
      { "name" => "Average Score", "name_slug" => "average_score", "type" => "Computed",
        "html_type" => "number", "readonly" => true, "storage" => "computed",
        "visibility" => { "admin" => true, "member" => true, "public" => false },
        "config" => {
          "bridge_entity_id" => bridge.id, "bridge_role" => "source",
          "source_slug" => "score", "function" => "avg", "precision" => 2
        } }
    ]
    host.save(validate: false)

    john = create(:entity_entry, entity: host, customer: customer, data: {}.to_json)
    jane = create(:entity_entry, entity: host, customer: customer, data: {}.to_json)
    math = create(:entity_entry, entity: klass, customer: customer, data: {}.to_json)
    create(:entity_entry, entity: bridge, customer: customer,
      data: { "student_surf" => john.id.to_s, "class_surf" => math.id.to_s, "score" => "90" }.to_json)
    create(:entity_entry, entity: bridge, customer: customer,
      data: { "student_surf" => john.id.to_s, "class_surf" => math.id.to_s, "score" => "85" }.to_json)
    create(:entity_entry, entity: bridge, customer: customer,
      data: { "student_surf" => jane.id.to_s, "class_surf" => math.id.to_s, "score" => "80" }.to_json)

    computed_surface = Member::Surface.new(
      key:   :computed_students,
      label: "Students",
      icon:  :rectangle_stack,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Students",
        subtitle: "Roster",
        scope: ->(_u) { EntityEntry.where(customer_id: customer.id, entity_id: host.id).order(:id) },
        columns: [
          { key: :average_score, label: "Average Score",
            value: ->(r) { r.display_text("average_score") }, format: :number, align: :right }
        ],
        empty_state: { headline: "None", body: "yet", icon: :rectangle_stack },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(r) { "##{r.id}" },
        sections: [{ key: :primary, rows: [
          { key: :average_score, label: "Average Score", value: ->(r) { r.display_text("average_score") } }
        ] }]
      )
    )
    @stub_surfaces << computed_surface

    queries = []
    subscriber = lambda do |*, payload|
      sql = payload[:sql].to_s
      queries << sql if sql.match?(/\ASELECT "entity_entries"\."id", /)
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get "/#{customer.id}/member/computed_students"
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("87.5")
    expect(response.body).to include("80")
    expect(queries.size).to eq(1)
  end

  it "shows a referenced instructor's name only when the label field is visible to members" do
    visible_instructor = create(:entity, customer: customer, name: "InstructorVisible", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
    ].to_json)
    hidden_instructor = create(:entity, customer: customer, name: "InstructorHidden", property_schema: [
      { "name" => "Name", "name_slug" => "name", "html_type" => "text",
        "visibility" => { "admin" => true, "member" => false, "public" => false } }
    ].to_json)
    jenny = create(:entity_entry, :with_data, customer: customer, entity: visible_instructor,
                   entry_data: { "name" => "Jenny" })
    irene = create(:entity_entry, :with_data, customer: customer, entity: hidden_instructor,
                   entry_data: { "name" => "Irene" })
    visible_course = create(:entity, customer: customer, name: "CourseVisible", property_schema: [
      { "name" => "Instructor", "name_slug" => "instructor", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => visible_instructor.id.to_s,
                      "label_field" => "name" } }
    ].to_json)
    hidden_course = create(:entity, customer: customer, name: "CourseHidden", property_schema: [
      { "name" => "Instructor", "name_slug" => "instructor", "html_type" => "select",
        "config" => { "options_source" => "entity_entries", "entity_id" => hidden_instructor.id.to_s,
                      "label_field" => "name" } }
    ].to_json)
    visible_row = create(:entity_entry, :with_data, customer: customer, entity: visible_course, user: user,
                         entry_data: { "instructor" => jenny.id.to_s })
    hidden_row = create(:entity_entry, :with_data, customer: customer, entity: hidden_course, user: user,
                        entry_data: { "instructor" => irene.id.to_s })

    @stub_surfaces << Member::Surface.new(
      key: :course_instructors,
      label: "Courses",
      icon: :rectangle_stack,
      enabled_for: ->(_u) { true },
      index: Member::Surface::Index.new(
        title: "Courses",
        subtitle: "Roster",
        scope: ->(_u) {
          EntityEntry.where(customer_id: customer.id, entity_id: [visible_course.id, hidden_course.id]).order(:id)
        },
        columns: [
          { key: :instructor, label: "Instructor", value: ->(r) { r.display_text("instructor") }, format: :string }
        ],
        empty_state: { headline: "None", body: "yet", icon: :rectangle_stack },
        per_page: 20
      ),
      detail: Member::Surface::Detail.new(
        title: ->(r) { "##{r.id}" },
        sections: [{ key: :primary, rows: [
          { key: :instructor, label: "Instructor", value: ->(r) { r.display_text("instructor") } }
        ] }]
      )
    )

    get "/#{customer.id}/member/course_instructors"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Jenny")
    expect(response.body).to include(irene.id.to_s)
    expect(response.body).not_to include("Irene")

    get "/#{customer.id}/member/course_instructors/#{visible_row.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Jenny")

    get "/#{customer.id}/member/course_instructors/#{hidden_row.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(irene.id.to_s)
    expect(response.body).not_to include("Irene")
  end
end
