# frozen_string_literal: true

require "rails_helper"

# /:cid/admin/maintenance/entities/journeys (Admin::Maintenance::JourneysController)
RSpec.describe "Admin::Maintenance::Journeys", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, customer: customer, role: :admin) }
  let(:platform_owner) { find_or_create_platform_owner }

  def index_path(cid = customer.id) = "/#{cid}/admin/maintenance/entities/journeys"
  def workspace_path(domain) = "/#{customer.id}/admin/maintenance/entities?domain_id=#{domain.id}"
  def new_path(**query) = "/#{customer.id}/admin/maintenance/entities/journeys/new#{"?#{query.to_query}" if query.any?}"
  def journey_path(record) = "/#{customer.id}/admin/maintenance/entities/journeys/#{record.id}"
  def edit_path(record) = "#{journey_path(record)}/edit"

  let(:journey_domain) { create(:entity_domain, customer: customer, name: "School") }
  let(:guard_path) { new_path }

  it_behaves_like "a platform-owner-guarded GET"

  def step_rows
    [
      { key: "start", page_id: student_page.id.to_s, label: "" },
      { key: "relate_1", page_id: course_page.id.to_s, label: "Courses", inputs: { student: "start" }, repeat: "1" },
      { key: "finish", label: "", finish_kind: "record", finish_step: "start" }
    ]
  end

  def journey_params(**overrides)
    { journey: { name: "Enrolment", key: "enrolment", description: "", entity_domain_id: journey_domain.id.to_s,
                 visible_audiences: %w[admin], steps: step_rows }.merge(overrides) }
  end

  describe "refusals" do
    let(:journey) { create(:journey, customer: customer) }
    let(:valid_params) { { journey: { name: "Changed", key: journey.key, visible_audiences: %w[admin] } } }

    shared_examples "refused on every action" do
      it "refuses HTML requests and changes nothing" do
        get new_path
        expect(response).not_to have_http_status(:ok)
        get edit_path(journey)
        expect(response).not_to have_http_status(:ok)

        expect { post index_path, params: { journey: { name: "Theirs", key: "theirs", visible_audiences: %w[admin] } } }
          .not_to change(Journey, :count)
        expect(response).to have_http_status(:found)
        expect(response.location).not_to include("/admin/maintenance/entities/journeys")

        patch journey_path(journey), params: valid_params
        expect(journey.reload.name).not_to eq("Changed")
        expect { delete journey_path(journey) }.not_to change(Journey, :count)
      end

      it "gets 403 on JSON requests" do
        get new_path, as: :json
        expect(response).to have_http_status(:forbidden)
        get edit_path(journey), as: :json
        expect(response).to have_http_status(:forbidden)
        post index_path, params: valid_params, as: :json
        expect(response).to have_http_status(:forbidden)
        patch journey_path(journey), params: valid_params, as: :json
        expect(response).to have_http_status(:forbidden)
        delete journey_path(journey), as: :json
        expect(response).to have_http_status(:forbidden)
        expect(journey.reload.name).not_to eq("Changed")
      end
    end

    context "as a tenant admin of the same customer" do
      before { sign_in admin }

      it_behaves_like "refused on every action"

      it "shows the owner-required message" do
        get new_path
        expect(flash[:alert]).to eq(I18n.t("common.errors.authorization.platform_owner_required"))
      end
    end

    context "as a member of the same customer" do
      before { sign_in create(:user, :member, customer: customer) }

      it_behaves_like "refused on every action"
    end
  end

  context "as the platform owner on the tenant" do
    include_context "student course association"

    let(:student_page) { student_journey_page }
    let(:course_page) { course_journey_page }

    before { sign_in platform_owner }

    it "lists the tenant's journeys on their domain in the entities workspace" do
      create(:journey, customer: customer, entity_domain: journey_domain, name: "Enrolment")
      create(:journey, name: "Someone else's")

      get workspace_path(journey_domain)
      expect(response).to have_http_status(:ok)
      journeys = Nokogiri::HTML(response.body).at_css("[data-role='domain-journeys']")
      expect(journeys.text).to include("Enrolment", I18n.t("journeys.admin.new"))
      expect(journeys.text).not_to include("Someone else's")
    end

    it "opens the new form in the domain it was started from" do
      journey_domain
      create(:entity_domain, customer: customer, name: "Other")

      get new_path(domain_id: journey_domain.id)

      html = Nokogiri::HTML(response.body)
      expect(html.at_css("select[name='journey[entity_domain_id]'] option[selected]")["value"]).to eq(journey_domain.id.to_s)
      expect(html.at_css("main nav a[href='#{workspace_path(journey_domain)}']")).to be_present
    end

    it "refuses a journey without a domain" do
      expect { post index_path, params: journey_params(entity_domain_id: "") }.not_to change(Journey, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("maint_core.entity_domains.errors.domain_required"))
    end

    it "renders the new form with this customer's launched and shared pages and domains" do
      create(:entity_domain, customer: customer, name: "Enrolment domain")
      create(:entity_domain, name: "Foreign domain")
      student_page
      draft = Current.set(customer: customer) { create(:page, customer: customer, name: "Draft page") }
      shared = create(:page, :shared, launched: true, name: "Shared page")
      foreign = create(:page, launched: true, name: "Foreign page")

      get new_path
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      page_options = html.css("form#journey-form select[name='journey[steps][][page_id]'] option").map(&:text)
      expect(page_options).to include(student_page.name, shared.name)
      expect(page_options).not_to include(draft.name, foreign.name)
      domain_select = html.at_css("select[name='journey[entity_domain_id]']")
      expect(domain_select.css("option").map(&:text)).to include("Enrolment domain")
      expect(domain_select.css("option").map(&:text)).not_to include("Foreign domain")
      expect(domain_select.at_css("option[selected]")).to be_nil
      groups = html.css("form#journey-form select[name='journey[steps][][page_id]'] optgroup").map { |group| group["label"] }
      expect(groups).to include(student_entity.display_label)
      expect(html.at_css("a[href$='/copy']")).to be_nil
    end

    it "creates a journey and redirects to edit" do
      expect { post index_path, params: journey_params }.to change(Journey, :count).by(1)

      journey = Journey.last
      expect(response).to redirect_to(edit_path(journey))
      expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.created"))
      expect(journey).to have_attributes(customer_id: customer.id, name: "Enrolment", key: "enrolment",
                                         entity_domain_id: journey_domain.id)
      expect(journey.steps_definition.action_keys).to eq(%w[student_new student_add_course])
    end

    it "re-renders with the definition errors when the steps are invalid" do
      rows = step_rows.tap { |list| list[1] = list[1].merge(inputs: { student: "" }) }

      expect { post index_path, params: journey_params(steps: rows) }.not_to change(Journey, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML(response.body).at_css("[role='alert']").text)
        .to include(I18n.t("journeys.definition.errors.relate_needs_input", step: "Courses"))
    end

    it "keeps an unkeyed page's choice when a refused save rolls its new action key back" do
      unkeyed = journey_page(student_entity, action_key: nil, fields: [journey_text_field("full_name")],
                                             form_settings: { modes: ["create"] }, name: "Unkeyed intake")
      rows = step_rows.tap do |list|
        list[0] = list[0].merge(page_id: unkeyed.id.to_s)
        list[1] = list[1].merge(inputs: { student: "" })
      end

      post index_path, params: journey_params(steps: rows)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(unkeyed.reload.action_key).to be_nil
      selects = Nokogiri::HTML(response.body).css("[data-journey-builder-target='list'] select[name='journey[steps][][page_id]']")
      expect(selects.first.at_css("option[selected]")&.[]("value")).to eq(unkeyed.id.to_s)
      expect(selects[1].at_css("option[selected]")&.[]("value")).to eq(course_page.id.to_s)
    end

    it "gets 403 on a JSON request for the new form as a tenant admin" do
      sign_in admin
      get new_path, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "renders the editor with launch, preview, create-page and delete actions" do
      journey = create(:journey, customer: customer, key: "enrolment")
      student_page

      get edit_path(journey)
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      builder = html.at_css("[data-controller='journey-builder']")
      expect(builder.css("[data-journey-builder-target='list'] > [data-journey-builder-target='row']").size).to eq(2)
      expect(builder.css("[data-journey-builder-target='row'][data-finish]").size).to eq(1)
      preview = html.at_css("a[target='_blank'][href*='journey=enrolment']")
      expect(preview["href"]).to start_with("/#{customer.id}/admin/entities/#{student_entity.id}/entries/new")
      expect(preview["href"]).to include("page=#{student_page.id}")
      expect(html.at_css("a[target='_blank'][href='/#{customer.id}/admin/maintenance/pages/new']")).to be_present
      expect(html.at_css("a[href='#{journey_path(journey)}/launch'][data-turbo-method='post']")).to be_present
      expect(html.at_css("a[href='#{journey_path(journey)}/copy'][data-turbo-method='post']").text)
        .to include(I18n.t("journeys.admin.duplicate"))
      expect(response.body).to include(I18n.t("journeys.admin.delete_confirm"))
    end

    it "previews a journey that starts by creating a user on the users screen" do
      journey = create(:journey, customer: customer, key: "register", definition: { "steps" => [
        { "key" => "user", "kind" => "user" },
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
      ] }.to_json)

      get edit_path(journey)

      preview = Nokogiri::HTML(response.body).at_css("a[target='_blank'][href*='journey=register']")
      expect(preview["href"]).to eq("/#{customer.id}/admin/modules/authentication/users/new?journey=register")
    end

    it "saves a user start, then the person page as its create step" do
      start_page = student_page
      rows = [{ key: "start", page_id: start_page.id.to_s, label: "" },
              { key: "finish", label: "", finish_kind: "record", finish_step: "start" }]

      post index_path, params: journey_params(start: { kind: "user", key: "" }, steps: rows)

      journey = Journey.last
      expect(response).to redirect_to(edit_path(journey))
      expect(journey.steps_definition.steps.map { |step| [step.key, step.kind] })
        .to eq([%w[user user], %w[start create], %w[finish finish]])
    end

    it "offers take offline for a launched journey and no preview without a first page" do
      journey = create(:journey, :launched, customer: customer)

      get edit_path(journey)
      expect(response.body).to include(I18n.t("journeys.admin.take_offline"))
      expect(Nokogiri::HTML(response.body).at_css("a[href*='journey=']")).to be_nil
    end

    it "renders the editor in zh-CN" do
      journey = create(:journey, customer: customer)

      get edit_path(journey), params: { locale: "zh-CN" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("业务域", "基本信息", "步骤", "添加步骤")
      expect(response.body).to include(I18n.t("journeys.admin.step_optional", locale: :"zh-CN"),
                                       I18n.t("journeys.admin.finish_message", locale: :"zh-CN"),
                                       I18n.t("journeys.admin.readiness.title", locale: :"zh-CN"))
    end

    it "updates a journey" do
      journey = create(:journey, customer: customer, key: "enrolment")

      patch journey_path(journey), params: journey_params(name: "Renamed")
      expect(response).to redirect_to(edit_path(journey))
      expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.updated"))
      expect(journey.reload.name).to eq("Renamed")
    end

    it "refuses to save a launched journey into a state that fails the launch checks" do
      student_page
      course_page
      journey = create(:journey, :launched, customer: customer, key: "enrolment", name: "Live")

      patch journey_path(journey), params: journey_params(name: "Renamed", visible_audiences: %w[admin member])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("journeys.launch.errors.page_missing", step: "start",
                                                                                   audience: I18n.t("journeys.audiences.member")))
      expect(journey.reload).to have_attributes(name: "Live", visible_audiences: %w[admin])
    end

    it "404s for another customer's journey" do
      foreign = create(:journey, name: "Theirs")

      get "/#{customer.id}/admin/maintenance/entities/journeys/#{foreign.id}/edit"
      expect(response).to have_http_status(:not_found)
      sign_in platform_owner
      patch "/#{customer.id}/admin/maintenance/entities/journeys/#{foreign.id}", params: journey_params(name: "Mine")
      expect(response).to have_http_status(:not_found)
      sign_in platform_owner
      delete "/#{customer.id}/admin/maintenance/entities/journeys/#{foreign.id}"
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.name).to eq("Theirs")
    end

    it "deletes a journey and its runs" do
      journey = create(:journey, customer: customer)
      other = create(:journey, customer: customer)
      JourneyRun.issue!(customer_id: customer.id, user: nil, session: {}, journey: journey, current_step: "start")
      JourneyRun.issue!(customer_id: customer.id, user: nil, session: {}, journey: other, current_step: "start")

      expect { delete journey_path(journey) }.to change(Journey, :count).by(-1).and change(JourneyRun, :count).by(-1)
      expect(response).to redirect_to(workspace_path(journey.entity_domain))
      expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.deleted"))
      expect(JourneyRun.where(journey_id: journey.id)).to be_empty
    end

    describe "posting the rendered form" do
      let(:second_course_page) do
        course_journey_page(action_key: "student_add_course_again", name: "Add another course")
      end

      # Collects the submittable fields of the rendered form in document order,
      # the way a browser serialises it (checked boxes only, template rows excluded).
      def form_pairs(html)
        form = Nokogiri::HTML(html).at_css("form#journey-form")
        form.css("input, select, textarea").each_with_object([]) do |field, pairs|
          next if field["name"].blank? || field.ancestors("template").any?
          next if %w[checkbox radio].include?(field["type"]) && !field.key?("checked")

          value = field.name == "select" ? (field.at_css("option[selected]") || field.at_css("option"))&.[]("value") : (field["value"] || field.text)
          pairs << [field["name"], value.to_s]
        end
      end

      def post_form(record, pairs)
        patch journey_path(record), params: URI.encode_www_form(pairs.reject { |name, _| name == "_method" }),
                                    headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
      end

      def stored_steps(record) = record.reload.steps_definition.to_h["steps"]

      it "round-trips a create, a repeating relate and a finish" do
        student_page
        course_page
        journey = create(:journey, customer: customer, key: "enrolment")

        get edit_path(journey)
        post_form(journey, form_pairs(response.body))

        expect(response).to redirect_to(edit_path(journey))
        expect(stored_steps(journey)).to eq([
          { "key" => "start", "kind" => "create", "action_key" => "student_new", "inputs" => {}, "repeat" => false,
            "optional" => false },
          { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" },
            "repeat" => true, "optional" => false },
          { "key" => "finish", "kind" => "finish", "inputs" => {}, "repeat" => false, "optional" => false,
            "target" => { "kind" => "record", "step" => "start" } }
        ])
      end

      it "keeps each row's values when a middle row's repeat box is unchecked" do
        student_page
        course_page
        second_course_page
        journey = create(:journey, customer: customer, key: "enrolment", definition: {
          "steps" => [
            { "key" => "start", "kind" => "create", "action_key" => "student_new" },
            { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" } },
            { "key" => "relate_2", "kind" => "relate", "action_key" => "student_add_course_again",
              "inputs" => { "student" => "start" }, "repeat" => true, "label" => "Again" },
            { "key" => "finish", "kind" => "finish", "target" => { "kind" => "page", "action_key" => "student_new" } }
          ]
        }.to_json)

        get edit_path(journey)
        pairs = form_pairs(response.body)
        expect(pairs.count { |name, _| name == "journey[steps][][repeat]" }).to eq(1)
        post_form(journey, pairs)

        expect(response).to redirect_to(edit_path(journey))
        steps = stored_steps(journey)
        expect(steps.map { |step| step.values_at("key", "action_key", "repeat", "optional") }).to eq([
          ["start", "student_new", false, false], ["relate_1", "student_add_course", false, false],
          ["relate_2", "student_add_course_again", true, false], ["finish", nil, false, false]
        ])
        expect(steps[2]).to include("label" => "Again", "inputs" => { "student" => "start" })
        expect(steps[3]["target"]).to eq("kind" => "page", "action_key" => "student_new")
      end

      describe "a journey that starts from an existing record" do
        let(:record_steps) do
          [{ key: "courses", page_id: course_page.id.to_s, label: "", inputs: { student: "record" }, repeat: "1" },
           { key: "finish", label: "", finish_kind: "record", finish_step: "record" }]
        end
        let(:expected_steps) do
          [{ "key" => "record", "kind" => "record", "entity_id" => student_entity.id.to_s, "inputs" => {}, "repeat" => false,
             "optional" => false },
           { "key" => "courses", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "record" },
             "repeat" => true, "optional" => false },
           { "key" => "finish", "kind" => "finish", "inputs" => {}, "repeat" => false, "optional" => false,
             "target" => { "kind" => "record", "step" => "record" } }]
        end

        it "saves the start record ahead of a first row that fills from it, and round-trips it through the editor" do
          post index_path, params: journey_params(key: "add_courses", start: { kind: "record", entity_id: student_entity.id.to_s, key: "record" },
                                                  steps: record_steps)
          journey = Journey.last
          expect(response).to redirect_to(edit_path(journey))
          expect(journey.steps_definition.to_h["steps"]).to eq(expected_steps)

          get edit_path(journey)
          pairs = form_pairs(response.body)
          expect(pairs).to include(["journey[start][kind]", "record"], ["journey[start][entity_id]", student_entity.id.to_s])
          post_form(journey, pairs)
          expect(stored_steps(journey)).to eq(expected_steps)
        end

        it "keeps the posted start when the record type is missing" do
          expect do
            post index_path, params: journey_params(start: { kind: "record", entity_id: "", key: "record" }, steps: record_steps)
          end.not_to change(Journey, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          html = Nokogiri::HTML(response.body)
          expect(html.at_css("[role='alert']").text).to include(I18n.t("journeys.definition.errors.record_entity_invalid", step: "record"))
          expect(html.at_css("input[name='journey[start][kind]'][value='record'][checked]")).to be_present
        end
      end
    end

    describe "optional steps, finish message and readiness" do
      it "round-trips an optional later row" do
        rows = step_rows.tap { |list| list[1] = list[1].merge(optional: "1") }

        post index_path, params: journey_params(steps: rows)
        journey = Journey.last
        expect(response).to redirect_to(edit_path(journey))
        expect(journey.steps_definition.step("relate_1").optional).to be(true)

        get edit_path(journey)
        rows = Nokogiri::HTML(response.body).css("[data-journey-builder-target='list'] > [data-journey-builder-target='row']")
        expect(rows[1].at_css("input[name='journey[steps][][optional]'][checked]")).to be_present
        expect(rows[0].at_css("input[name='journey[steps][][optional]'][checked]")).to be_nil
      end

      it "round-trips a later row an earlier step's processing may leave out, never the first" do
        rows = step_rows.tap do |list|
          list[0] = list[0].merge(conditional: "1")
          list[1] = list[1].merge(conditional: "1")
        end

        post index_path, params: journey_params(steps: rows)
        journey = Journey.last
        expect(response).to redirect_to(edit_path(journey))
        expect(journey.steps_definition.first_step).not_to be_conditional
        expect(journey.steps_definition.step("relate_1")).to be_conditional

        get edit_path(journey)
        rows = Nokogiri::HTML(response.body).css("[data-journey-builder-target='list'] > [data-journey-builder-target='row']")
        expect(rows[1].at_css("input[name='journey[steps][][conditional]'][checked]")).to be_present
        expect(rows[0].at_css("input[name='journey[steps][][conditional]'][checked]")).to be_nil
        expect(rows[1].at_css("[data-step-effects]")).to be_present
      end

      it "does not store the first step as optional" do
        rows = step_rows.tap { |list| list[0] = list[0].merge(optional: "1") }

        post index_path, params: journey_params(steps: rows)
        journey = Journey.last
        expect(response).to redirect_to(edit_path(journey))
        expect(journey.steps_definition.first_step.optional).to be(false)
      end

      it "refuses a record finish that names an optional step" do
        rows = step_rows.tap do |list|
          list[1] = list[1].merge(optional: "1")
          list[2] = list[2].merge(finish_step: "relate_1")
        end

        expect { post index_path, params: journey_params(steps: rows) }.not_to change(Journey, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(Nokogiri::HTML(response.body).at_css("[role='alert']").text)
          .to include(I18n.t("journeys.definition.errors.finish_record_optional"))
      end

      it "strips and truncates the finish message" do
        long = " #{'x' * 310} "
        rows = step_rows.tap { |list| list[2] = list[2].merge(finish_message: long) }

        post index_path, params: journey_params(steps: rows)
        journey = Journey.last
        expect(journey.steps_definition.finish_message).to eq("x" * 300)

        rows = step_rows.tap { |list| list[2] = list[2].merge(finish_message: "  Thanks  ") }
        patch journey_path(journey), params: journey_params(steps: rows)
        expect(journey.reload.steps_definition.finish_message).to eq("Thanks")

        get edit_path(journey)
        message = Nokogiri::HTML(response.body).at_css("input[name='journey[steps][][finish_message]']")
        expect(message["value"]).to eq("Thanks")
        expect(message["maxlength"]).to eq("300")
      end

      it "drops an input posted for a field the page does not lock" do
        rows = step_rows.tap { |list| list[1] = list[1].merge(inputs: { student: "start", extra: "start" }) }

        post index_path, params: journey_params(steps: rows)
        journey = Journey.last
        expect(journey.steps_definition.step("relate_1").inputs).to eq("student" => "start")
      end

      it "shows the ready status on a draft whose launch checks pass" do
        student_page
        course_page
        journey = create(:journey, customer: customer)

        get edit_path(journey)
        html = Nokogiri::HTML(response.body)
        expect(html.at_css("#journey-readiness-title").text).to include(I18n.t("journeys.admin.readiness.title"))
        expect(html.at_css("[role='status']").text).to include(I18n.t("journeys.admin.readiness.ready"))
      end

      it "lists an unbound locked input on a draft that is not ready" do
        student_page
        journey_page(bridge_entity, action_key: "student_add_course",
                                    fields: [journey_reference_field("student", student_entity, "full_name"),
                                             journey_reference_field("course", course_entity, "code"),
                                             journey_text_field("status")],
                                    form_settings: { modes: ["create"],
                                                     inputs: [{ field: "student", entity_id: student_entity.id },
                                                              { field: "course", entity_id: course_entity.id }] })
        journey = create(:journey, customer: customer)

        get edit_path(journey)
        html = Nokogiri::HTML(response.body)
        expect(html.at_css("#journey-readiness-title + p").text).to include(I18n.t("journeys.admin.readiness.issues"))
        expect(html.at_css("[role='list']").text).to include(
          I18n.t("journeys.launch.errors.input_unbound", step: "relate_1", audience: I18n.t("journeys.audiences.admin"),
                                                        field: "Course")
        )
      end

      it "does not show the readiness card on the new form or a launched journey" do
        student_page
        course_page

        get new_path
        expect(Nokogiri::HTML(response.body).at_css("#journey-readiness-title")).to be_nil

        journey = create(:journey, :launched, customer: customer)
        get edit_path(journey)
        expect(Nokogiri::HTML(response.body).at_css("#journey-readiness-title")).to be_nil
      end
    end

    describe "a Student → Course → Enrolment journey" do
      let(:course_create_page) { course_create_journey_page }
      let(:enrolment_page) { enrolment_journey_page }

      def enrolment_rows
        [
          { key: "start", page_id: student_page.id.to_s, label: "" },
          { key: "course", page_id: course_create_page.id.to_s, label: "Course" },
          { key: "enrol", page_id: enrolment_page.id.to_s, label: "Enrol",
            inputs: { student: "start", course: "course" } },
          { key: "finish", finish_kind: "record", finish_step: "start" }
        ]
      end

      it "stores both locked inputs and passes the launch checks" do
        expect { post index_path, params: journey_params(steps: enrolment_rows) }.to change(Journey, :count).by(1)

        journey = Journey.last
        enrol = journey.steps_definition.step("enrol")
        expect(enrol).to have_attributes(kind: "relate", inputs: { "student" => "start", "course" => "course" })
        expect(Journeys::LaunchChecks.new(journey).errors).to eq([])

        post "#{journey_path(journey)}/launch"
        expect(response).to redirect_to(edit_path(journey))
        expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.launched"))
        expect(journey.reload).to be_launched

        get edit_path(journey)
        html = Nokogiri::HTML(response.body)
        expect(html.at_css("#journey-readiness-title")).to be_nil
        fill = html.css("[data-journey-builder-target='list'] > [data-journey-builder-target='row']")[2]
        expect(fill.at_css("select[name='journey[steps][][inputs][student]'] option[selected]")["value"]).to eq("start")
        expect(fill.at_css("select[name='journey[steps][][inputs][course]'] option[selected]")["value"]).to eq("course")
      end
    end
  end
end
