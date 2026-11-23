# frozen_string_literal: true

require "rails_helper"

# A fully established sign-in completes the
# pending claim recorded by register_member. Each example starts from that
# public submission.
RSpec.describe "Pending claims on sign-in", type: :request do
  # Devise mail is enqueued; deliver it so examples can read the mailbox.
  around { |example| perform_enqueued_jobs { example.run } }

  let_it_be(:customer) { create(:customer) }
  let_it_be(:other_customer) { create(:customer) }
  let(:action_key) { "enroll" }
  let(:student_entity) { build_student_entity(customer) }
  let(:public_page) do
    build_public_registration_page(
      customer: customer, entity: student_entity, action_key: action_key, traits: %i[public_only]
    )
  end
  let(:course_entity) do
    create(:entity, customer: customer, name: "Course",
           property_schema: [{ "name" => "Title", "name_slug" => "title", "html_type" => "text" }].to_json)
  end
  let(:course_entry) do
    create(:entity_entry, :with_data, entity: course_entity, customer: customer,
           entry_data: { "title" => "Algebra" })
  end
  let(:enroll_entity) do
    create(:entity, customer: customer, name: "EnrollmentForm", property_schema: [
      { "name" => "Course", "name_slug" => "course", "type" => Entity::ENTITY_REFERENCE_TYPE,
        "entity_id" => course_entity.id, "html_type" => "select" }
    ].to_json)
  end
  let(:member_page) do
    config = {
      "metadata" => { "entity_id" => enroll_entity.id, "entity_name" => enroll_entity.name },
      "pages" => [ {
        "id" => "p1",
        "fields" => [ {
          "id" => "course", "property_slug" => "course", "html_type" => "select", "source" => "entity",
          "label" => "Course",
          "dynamic_options" => { "options_source" => "entity_entries", "entity_id" => course_entity.id.to_s,
                                 "label_field" => "title" }
        } ]
      } ]
    }
    Current.set(customer: customer) do
      create(:page, :member_only, :launched, customer: customer, entity: enroll_entity,
             action_key: action_key, configuration: config.to_json)
    end
  end
  let(:continuation_path) do
    Pages::ActionLink.path(
      customer_id: customer.id, action_key: action_key, prefill: { "course" => course_entry.id.to_s }
    )
  end

  before do
    stub_member_quota_allow!
    enable_authentication_signup!(customer)
    enable_module!("authentication", other_customer)
    Authentication::Throttle.reset_store!
    ActionMailer::Base.deliveries.clear
    public_page
    flowchart = Flowchart.find(public_page.flowchart_id)
    flowchart.update_column(:activity, ActivityGenerator.new(flowchart).generate)
    member_page
    course_entry
  end

  after { Authentication::Throttle.reset_store! }

  def register_from_action(email)
    get "/#{customer.id}/actions/#{action_key}", params: { prefill: { course: course_entry.id } }
    expect(response).to have_http_status(:see_other)
    query = Rack::Utils.parse_nested_query(URI.parse(response.location).query.to_s)
    token = query["continuation"]
    expect(token).to be_present
    expect(Pages::Continuation.verify(token)).to include(
      action_key: action_key,
      prefill: { "course" => course_entry.id.to_s }
    )

    get response.location
    expect(response.body).to include(%(name="_continuation"), %(value="#{token}"))

    post "/#{customer.id}/page/#{public_page.public_uuid}", params: {
      identity: { first_name: "Pat", last_name: "Lee", email: email },
      _continuation: token
    }
    expect(response).to have_http_status(:redirect)
    expect(flash[:notice]).to eq(I18n.t("public_views.flash.outcomes.registration_pending"))
  end

  def mail_token(param)
    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    body = mail.text_part&.body.to_s
    body = mail.body.to_s if body.blank?
    token = body[/#{Regexp.escape(param)}=([^"&\s]+)/, 1]
    expect(token).to be_present
    token
  end

  def confirm_last_email
    get "/auth/confirmation", params: { confirmation_token: mail_token("confirmation_token") }
  end

  def consume_last_sign_in_link
    perform_enqueued_jobs
    get sign_in_link_path, params: { token: mail_token("token") }
  end

  def student_entry_for(email)
    EntityEntry.find_by!(entity: student_entity, customer: customer).tap do |entry|
      expect(entry.data_json["email"]).to eq(email)
    end
  end

  def selected_course_option
    Nokogiri::HTML(response.body).at_css(%(option[value="#{course_entry.id}"][selected]))
  end

  it "confirms a new visitor, links the Student entry, and lands on the member Enroll page" do
    email = "fresh-claim@example.com"
    register_from_action(email)
    created = Authentication::User.find_by_normalized_email(email)
    entry = student_entry_for(email)
    expect(entry.user_id).to be_nil
    expect(People::PendingClaim.find_by!(user_id: created.id)).to be_present

    confirm_last_email

    expect(controller.user_signed_in?).to be(true)
    expect(controller.current_user).to eq(created)
    expect(entry.reload.user_id).to eq(created.id)
    expect(People::PendingClaim.find_by(user_id: created.id)).to be_nil
    expect(response).to redirect_to(continuation_path)

    follow_redirect!
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(
      "#{member_page_path(customer_id: customer.id, id: member_page.id)}?#{ { prefill: { "course" => course_entry.id.to_s } }.to_query }"
    )

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(selected_course_option).to be_present
  end

  it "completes the claim when the confirmation link is opened in a fresh session" do
    email = "fresh-device@example.com"
    register_from_action(email)
    created = Authentication::User.find_by_normalized_email(email)
    entry = student_entry_for(email)
    token = mail_token("confirmation_token")

    reset!

    get "/auth/confirmation", params: { confirmation_token: token }

    expect(controller.user_signed_in?).to be(true)
    expect(controller.current_user).to eq(created)
    expect(entry.reload.user_id).to eq(created.id)
    expect(People::PendingClaim.find_by(user_id: created.id)).to be_nil
    expect(response).to redirect_to(continuation_path)
  end

  it "keeps the claim pending through the password step and completes it after MFA" do
    member = create(:user, :member, :with_mfa, customer: customer,
                    email: "mfa-claim@example.com", password: "password123")
    register_from_action(member.email)
    claim = People::PendingClaim.find_by!(user_id: member.id)
    expect(claim.entity_entry_id).to be_nil

    post user_session_path, params: { user: { email: member.email, password: "password123" } }

    expect(response).to redirect_to(mfa_session_path(customer.id))
    expect(People::PendingClaim.find_by(user_id: member.id)).to eq(claim)
    expect(EntityEntry.where(entity: student_entity, customer: customer).where.not(user_id: nil)).to be_empty

    post mfa_session_path(customer.id), params: { otp_code: ROTP::TOTP.new(member.otp_secret).now }

    expect(People::PendingClaim.find_by(user_id: member.id)).to be_nil
    expect(response).to redirect_to(continuation_path)
  end

  it "keeps the claim pending until a started MFA enrollment is completed" do
    member = create(:user, :member, :mfa_configured, customer: customer,
                    email: "setup-claim@example.com", password: "password123")
    register_from_action(member.email)
    claim = People::PendingClaim.find_by!(user_id: member.id)

    post user_session_path, params: { user: { email: member.email, password: "password123" } }

    expect(response).to redirect_to(mfa_setup_path(customer.id))
    expect(People::PendingClaim.find_by(user_id: member.id)).to eq(claim)

    get mfa_setup_path(customer.id)
    post mfa_setup_path(customer.id), params: { otp_code: ROTP::TOTP.new(member.reload.otp_secret).now }

    expect(People::PendingClaim.find_by(user_id: member.id)).to be_nil
    expect(response).to redirect_to(continuation_path)
  end

  it "lands an existing member on the continuation through the emailed sign-in link and links nothing" do
    member = create(:user, :member, customer: customer, email: "existing-claim@example.com")
    register_from_action(member.email)
    expect(People::PendingClaim.find_by!(user_id: member.id).entity_entry_id).to be_nil
    expect(EntityEntry.where(entity: student_entity, customer: customer)).to be_empty

    consume_last_sign_in_link

    expect(controller.user_signed_in?).to be(true)
    expect(controller.current_user).to eq(member)
    expect(EntityEntry.where(entity: student_entity, customer: customer)).to be_empty
    expect(People::PendingClaim.find_by(user_id: member.id)).to be_nil
    expect(response).to redirect_to(continuation_path)
  end

  it "prefers a stored location over the continuation and still consumes the claim" do
    email = "stored-return@example.com"
    register_from_action(email)
    created = Authentication::User.find_by_normalized_email(email)
    entry = student_entry_for(email)
    stored = member_dashboard_path(customer.id)

    get stored
    expect(response).to redirect_to(new_user_session_path)
    expect(session["user_return_to"]).to eq(stored)

    confirm_last_email

    expect(entry.reload.user_id).to eq(created.id)
    expect(People::PendingClaim.find_by(user_id: created.id)).to be_nil
    expect(response).to redirect_to(stored)
  end

  it "ignores an expired claim and leaves the Student entry unlinked" do
    email = "expired-claim@example.com"
    register_from_action(email)
    created = Authentication::User.find_by_normalized_email(email)
    entry = student_entry_for(email)
    claim = People::PendingClaim.find_by!(user_id: created.id)
    claim.update_columns(expires_at: 1.minute.ago)

    confirm_last_email

    expect(controller.user_signed_in?).to be(true)
    expect(entry.reload.user_id).to be_nil
    expect(People::PendingClaim.find(claim.id)).to eq(claim)
    expect(response).to redirect_to(member_dashboard_path(customer.id))
  end

  it "never completes a claim for another tenant's user" do
    email = "tenant-one@example.com"
    register_from_action(email)
    created = Authentication::User.find_by_normalized_email(email)
    entry = student_entry_for(email)
    claim = People::PendingClaim.find_by!(user_id: created.id)

    stranger = create(:user, :member, customer: other_customer, password: "password123")
    post user_session_path, params: { user: { email: stranger.email, password: "password123" } }

    expect(controller.current_user).to eq(stranger)
    expect(People::PendingClaim.find(claim.id)).to eq(claim)
    expect(entry.reload.user_id).to be_nil
    expect(response).to redirect_to(member_dashboard_path(other_customer.id))
  end
end
