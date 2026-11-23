# frozen_string_literal: true

require "rails_helper"

# A journey that opens with a user step: an admin creates the account on
# Authentication › Users › New (with a random password), then the run
# continues on the person page, whose new record is linked to that account.
RSpec.describe "Journey that starts by creating a user", type: :request do
  include_context "as admin"
  include_context "student course association"

  let(:user_definition) do
    { "steps" => [
      { "key" => "user", "kind" => "user" },
      { "key" => "start", "kind" => "create", "action_key" => "student_new" },
      { "key" => "relate_1", "kind" => "relate", "action_key" => "student_add_course", "inputs" => { "student" => "start" }, "repeat" => true },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
    ] }.to_json
  end
  let!(:student_page) { student_journey_page }
  let!(:course_page) { course_journey_page }
  let!(:journey) { create(:journey, :launched, customer: customer, key: "register_student", definition: user_definition) }

  let(:new_user_path) { new_admin_modules_authentication_user_path(customer.id) }
  let(:users_path) { admin_modules_authentication_users_path(customer.id) }
  let(:account_params) { { first_name: "Grace", last_name: "Hopper", email: "grace@example.com", role: "member" } }

  before do
    person_model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(person_model, true)
    student_entity.update_columns(extended_model: person_model)
  end

  def doc = Nokogiri::HTML(response.body)
  def progress = doc.at_css("[data-role='journey-progress']")
  def run_for(token) = JourneyRun.find_by(token_digest: JourneyRun.digest_for(token))
  def students = EntityEntry.where(customer_id: customer.id, entity_id: student_entity.id)

  def submit_path(page, **query)
    "/#{customer.id}/page/#{page.public_uuid}?#{{ return_to: PageRendering::ENTITY_ENTRY_RETURN }.merge(query).to_query}"
  end

  def create_account(**overrides)
    post users_path, params: { journey: journey.key, authentication_user: account_params.merge(overrides) }
    response.location && Addressable::URI.parse(response.location).query_values.to_h["run"]
  end

  it "opens the users screen without password fields, as the journey's first step" do
    get new_user_path, params: { journey: journey.key }

    expect(response).to have_http_status(:ok)
    expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 1, total: 3), I18n.t("journeys.runtime.user_step"))
    expect(doc.at_css("input[type='hidden'][name='journey']")["value"]).to eq(journey.key)
    expect(doc.at_css("input[name='authentication_user[password]']")).to be_nil
    expect(doc.at_css("input[name='authentication_user[password_confirmation]']")).to be_nil
    expect(response.body).to include(I18n.t("admin_modules.users.form.generated_password_hint"))
    expect(doc.at_css("input[type='submit']")["value"]).to eq(I18n.t("admin_modules.users.actions.create_user_and_continue"))
  end

  it "keeps the plain users screen asking for a password" do
    get new_user_path

    expect(progress).to be_nil
    expect(doc.at_css("input[name='journey']")).to be_nil
    expect(doc.at_css("input[name='authentication_user[password]']")).to be_present
  end

  it "creates the account with a random password, then links the person record saved on the next page" do
    token = nil
    expect { token = create_account(password: "ignored1", password_confirmation: "ignored1") }.to change(Authentication::User, :count).by(1)
    account = Authentication::User.find_by!(email: "grace@example.com")
    expect(account).to have_attributes(customer_id: customer.id, primary_role_key: "member")
    expect(account.encrypted_password).to be_present
    expect(account.valid_password?("ignored1")).to be(false)
    expect(flash[:notice]).to eq(I18n.t("admin_modules.flash.users.created", name: account.display_name))

    location = Addressable::URI.parse(response.location)
    expect(location.path).to eq(new_admin_entity_entry_path(customer.id, student_entity))
    expect(location.query_values).to include("page" => student_page.id.to_s, "run" => be_present)
    expect(run_for(token)).to have_attributes(journey_id: journey.id, current_step: "start", user_id: admin.id,
                                              records: { "user" => [account.id.to_s] })

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(progress.text).to include(I18n.t("journeys.runtime.step_of", current: 2, total: 3))

    expect { post submit_path(student_page), params: { _run: token, entity: { full_name: "Grace Hopper" } } }.to change(students, :count).by(1)
    student = students.order(:id).last
    expect(student.user_id).to eq(account.id)
    expect(run_for(token)).to have_attributes(current_step: "relate_1", records: include("start" => [student.id.to_s]))
    expect(Addressable::URI.parse(response.location).path).to eq(new_admin_entity_entry_path(customer.id, bridge_entity))
  end

  it "refuses the person page, saving nothing, when the account is already linked to another record" do
    token = create_account
    account = Authentication::User.find_by!(email: "grace@example.com")
    student.update_columns(user_id: account.id)

    expect { post submit_path(student_page), params: { _run: token, entity: { full_name: "Grace Hopper" } } }.not_to change(students, :count)
    expect(flash[:alert]).to include(I18n.t("people.errors.user_already_linked"))
    expect(run_for(token).current_step).to eq("start")
  end

  it "doesn't link a record saved on the person page outside a run" do
    expect { post submit_path(student_page), params: { entity: { full_name: "Ada Lovelace" } } }.to change(students, :count).by(1)

    expect(students.order(:id).last.user_id).to be_nil
  end

  it "sends New entry on the person entity to the users screen first, but not inside a run or the quick-add dialog" do
    get new_admin_entity_entry_path(customer.id, student_entity)
    expect(response).to have_http_status(:see_other)
    expect(response.location).to end_with("#{new_user_path}?journey=#{journey.key}")

    token = create_account
    get new_admin_entity_entry_path(customer.id, student_entity, page: student_page.id, run: token)
    expect(response).to have_http_status(:ok)

    get new_admin_entity_entry_path(customer.id, student_entity), headers: { "Turbo-Frame" => Admin::Entities::QuickAddDialogComponent.frame_id(0) }
    expect(response).to have_http_status(:ok)
  end

  it "opens New entry on the person page as usual while the journey is offline" do
    journey.update!(status: :draft)

    get new_admin_entity_entry_path(customer.id, student_entity)

    expect(response).to have_http_status(:ok)
  end

  it "takes an admin's start link to the users screen and sends anonymous visitors to sign in" do
    get "/#{customer.id}/journeys/#{journey.key}"
    expect(response).to have_http_status(:see_other)
    expect(response.location).to end_with("#{new_user_path}?journey=#{journey.key}")

    sign_out admin
    get "/#{customer.id}/journeys/#{journey.key}"
    expect(response).to redirect_to(new_user_session_path)
  end

  it "falls back to the plain users screen for a draft, unknown or other tenant's journey" do
    draft = create(:journey, customer: customer, key: "draft_register", definition: user_definition)
    foreign = create(:journey, :launched, key: "foreign_register", definition: user_definition)

    [draft.key, "nope", foreign.key, "register_student_x"].each do |key|
      get new_user_path, params: { journey: key }
      expect(response).to redirect_to(new_user_path)
      expect(flash[:alert]).to eq(I18n.t("journeys.runtime.unavailable"))
    end

    expect { post users_path, params: { journey: draft.key, authentication_user: account_params } }.not_to change(Authentication::User, :count)
    expect(response).to redirect_to(new_user_path)
  end

  it "creates no account when the run cannot be issued" do
    allow(JourneyRun).to receive(:issue!).and_raise(ActiveRecord::StatementInvalid, "run refused")

    expect { create_account }.to raise_error(ActiveRecord::StatementInvalid)
    expect(Authentication::User.exists?(email: "grace@example.com")).to be(false)
  end

  it "doesn't offer a member the start link" do
    sign_out admin
    sign_in create(:user, :member, customer: customer)

    get "/#{customer.id}/journeys/#{journey.key}"

    expect(response).to have_http_status(:not_found)
  end

  it "re-renders the journey form when the account is invalid, creating nothing" do
    expect { create_account(email: "") }.not_to change(Authentication::User, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(doc.at_css("input[type='hidden'][name='journey']")["value"]).to eq(journey.key)
    expect(JourneyRun.where(journey_id: journey.id)).to be_empty
  end
end
