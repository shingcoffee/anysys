# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "SMS audience/campaign HTTP security", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:base) { "/#{customer.id}/admin/modules/sms" }

  before do
    sms = FeatureModules::Module.find_by(key: "sms") || create(:feature_module, key: "sms", name: "SMS")
    sms.update!(status: :active)
    create(:customer_feature_module, customer: customer, feature_module: sms)
    sign_in admin
  end

  def data
    response.parsed_body.fetch("data")
  end

  def contact(customer: self.customer, phone: "+8613800138000", **attributes)
    Sms::Contact.create!({ customer: customer, phone_e164: phone, country_code: "CN", **attributes })
  end

  def campaign(customer: self.customer, **attributes)
    Sms::Campaign.create!({ customer: customer, created_by: admin, name: "Campaign", **attributes })
  end

  def grant(record)
    result = Sms::Contacts::RecordConsent.call(customer: record.customer, actor: admin, contact: record,
      attributes: { action: "granted", occurred_at: 1.minute.ago, reference: "Consent form", statement: "I agree", event_key: SecureRandom.uuid })
    expect(result).to be_success
    record.reload
  end

  it "blocks anonymous, member and foreign-tenant admin requests, and disabled modules" do
    sign_out admin
    get "#{base}/contacts.json"
    expect(response).to have_http_status(:unauthorized)
    sign_in create(:user, :member, customer: customer)
    get "#{base}/campaigns.json"
    expect(response).to have_http_status(:forbidden)
    sign_in create(:user, :admin)
    get "#{base}/segments.json"
    expect(response).to have_http_status(:forbidden)
    sign_in admin
    FeatureModules::CustomerAssignment.where(customer_id: customer.id).update_all(status: 1)
    get "#{base}/contacts.json"
    expect(response).to have_http_status(:not_found)
  end

  it "uses the URL customer for owner browsing and rejects cross-tenant IDs and parameter spoofing" do
    own = contact(name: "Tenant record")
    foreign = contact(customer: create(:customer), phone: "+8613800138001", name: "Other record")
    owner = find_or_create_platform_owner
    sign_in owner
    get "#{base}/contacts.json"
    expect(data.fetch("records").map { |row| row["id"] }).to eq([own.id])
    get "#{base}/contacts/#{foreign.id}.json"
    expect(response).to have_http_status(:not_found)
    post "#{base}/contacts.json", params: { customer_id: foreign.customer_id, sms_contact: { phone: "+8613800138002" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Sms::Contact.where(phone_e164: "+8613800138002")).not_to exist
  end

  it "creates unknown contacts, records evidence separately and returns conflicts on stale edits" do
    post "#{base}/contacts.json", params: { sms_contact: { phone: "13800138000", name: "Person", country_code: "CN", custom_attributes_json: '{"city":"Shanghai"}' } }, as: :json
    expect(response).to have_http_status(:created), response.body
    record = Sms::Contact.find(data.fetch("id"))
    expect(record.consent_status).to eq("unknown")
    post "#{base}/contacts/#{record.id}/consent_events.json", params: { sms_consent_event: { action: "granted", occurred_at: 1.minute.ago.iso8601,
      reference: "Signed form", statement: "Marketing SMS permitted", event_key: "admin-http-grant" } }, as: :json
    expect(response).to have_http_status(:created), response.body
    expect(record.reload.consent_status).to eq("granted")
    expect(record.consent_events.last.attributes).to include("source" => "admin", "actor_user_id" => admin.id, "customer_id" => customer.id)
    patch "#{base}/contacts/#{record.id}.json", params: { sms_contact: { name: "Old edit", lock_version: 0 } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(record.reload.name).to eq("Person")
  end

  it "rejects protected consent/source fields and unsafe JSON without mutation" do
    post "#{base}/contacts.json", params: { sms_contact: { phone: "+8613800138000", consent_status: "granted" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    ["{", "[]", '{"name":{},"name":{}}'].each do |json|
      post "#{base}/campaigns/preview.json", params: { sms_campaign: { name: "Unsaved", variable_map_json: json } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(Sms::Contact.count).to eq(0)
    expect(Sms::Campaign.count).to eq(0)
    post "#{base}/campaigns.json", params: { sms_campaign: { name: "x" * 65_536 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Sms::Campaign.count).to eq(0)
  end

  it "scopes evidence, draft actions and report/CSV lookups even for the platform owner" do
    foreign_customer = create(:customer)
    foreign_contact = contact(customer: foreign_customer)
    foreign_campaign = campaign(customer: foreign_customer, created_by: create(:user, :admin, customer: foreign_customer))
    sign_in find_or_create_platform_owner
    get "#{base}/campaigns/#{foreign_campaign.id}/report.json"
    expect(response).to have_http_status(:not_found)
    get "#{base}/campaigns/#{foreign_campaign.id}/report.csv"
    expect(response).to have_http_status(:not_found)
    post "#{base}/campaigns/#{foreign_campaign.id}/cancel.json", as: :json
    expect(response).to have_http_status(:not_found)
    post "#{base}/contacts/#{foreign_contact.id}/consent_events.json", params: { sms_consent_event: { action: "revoked", reference: "invalid", occurred_at: 1.minute.ago.iso8601, event_key: "foreign-revoke" } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(Sms::ConsentEvent.count).to eq(0)
    expect(foreign_campaign.reload.status).to eq("draft")
  end

  it "previews unsaved campaigns without a vendor call, writes, quota reservation or enqueue" do
    record = grant(contact(name: "Person"))
    template = create(:sms_template, purpose: "marketing", variables: ["name"], body_template: "Hi {{name}}")
    create(:sms_credential)
    expect(Sms::Gateway).not_to receive(:send)
    expect(Sms::Gateway).not_to receive(:send_campaign)
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    before_counts = [Sms::Message.count, Sms::Campaign.count, Sms::CampaignRecipient.count, Sms::ConsentEvent.count, enqueued_jobs.size]
    post "#{base}/campaigns/preview.json", params: { preview_contact_id: record.id,
      sms_campaign: { name: "Unsaved", template_id: template.id, variable_map_json: '{"name":{"source":"field","field":"name"}}' } }, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(data.fetch("preview")).to include("matched_count" => 1, "eligible_count" => 1, "review_token" => nil)
    expect(data.fetch("contacts").length).to be <= 20
    expect([Sms::Message.count, Sms::Campaign.count, Sms::CampaignRecipient.count, Sms::ConsentEvent.count, enqueued_jobs.size]).to eq(before_counts)
  end

  it "rejects foreign sample/segment IDs and preserves blank optional IDs for incomplete drafts" do
    foreign = contact(customer: create(:customer), phone: "+8613800138001")
    post "#{base}/campaigns/preview.json", params: { preview_contact_id: foreign.id, sms_campaign: { name: "Sample" } }, as: :json
    expect(response).to have_http_status(:not_found), response.body
    foreign_segment = Sms::Audience::Segment.create!(customer: foreign.customer, name: "Foreign")
    post "#{base}/campaigns.json", params: { sms_campaign: { name: "Invalid", segment_id: foreign_segment.id } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/campaigns.json", params: { sms_campaign: { name: "Incomplete draft", segment_id: "", template_id: "", variable_map_json: "{}" } }, as: :json
    expect(response).to have_http_status(:created)
    expect(Sms::Campaign.find(data.fetch("id"))).to have_attributes(status: "draft", segment_id: nil, template_id: nil)
  end

  it "requires saved review/version only at launch and disallows terminal cancellation" do
    draft = campaign
    post "#{base}/campaigns/#{draft.id}/launch.json", params: { lock_version: draft.lock_version, review_token: "invalid", sms_campaign: { name: "Injected" } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/campaigns/#{draft.id}/launch.json", params: { lock_version: draft.lock_version, review_token: "invalid" }, as: :json
    expect(response).to have_http_status(:conflict), response.body
    expect(draft.reload).to have_attributes(status: "draft", name: "Campaign")
    terminal = campaign(status: "completed")
    post "#{base}/campaigns/#{terminal.id}/cancel.json", as: :json
    expect(response).to have_http_status(:conflict)
  end

  it "launches only the saved reviewed draft and safely replays the same signed launch" do
    grant(contact)
    template = create(:sms_template, purpose: "marketing", variables: [], body_template: "Approved offer")
    create(:sms_credential)
    draft = campaign(template: template)
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    get "#{base}/campaigns/#{draft.id}.json"
    expect(response).to have_http_status(:ok)
    token = data.fetch("preview").fetch("review_token")
    expect(token).to be_present
    version = draft.lock_version
    2.times do
      post "#{base}/campaigns/#{draft.id}/launch.json", params: { lock_version: version, review_token: token }, as: :json
      expect(response).to have_http_status(:accepted), response.body
      expect(data.fetch("status")).to eq("scheduled")
      expect(data).not_to have_key("run_token")
      expect(data).not_to have_key("settings_snapshot")
    end
    expect(draft.reload.launched_by_id).to eq(admin.id)
    expect(Sms::Campaign.count).to eq(1)
    expect(Sms::CampaignRecipient.count).to eq(0)
    expect(Sms::Message.count).to eq(0)
  end

  it "cancels queued unattempted messages but retains already-attempted rows" do
    running = campaign(status: "running", started_at: Time.current, run_token: "lease")
    first = contact
    second = contact(phone: "+8613800138001")
    queued = create(:sms_message, customer: customer, campaign_id: running.id, contact_id: first.id, status: "queued")
    attempted = create(:sms_message, customer: customer, campaign_id: running.id, contact_id: second.id, status: "sent", dispatch_started_at: Time.current)
    [first, second].zip([queued, attempted]).each do |person, message|
      Sms::CampaignRecipient.create!(customer: customer, campaign: running, contact: person, phone_e164: person.phone_e164,
        message: message, status: "admitted", admitted_at: Time.current, contact_snapshot: { "name" => person.name })
    end
    post "#{base}/campaigns/#{running.id}/cancel.json", as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(running.reload).to have_attributes(status: "cancelled", run_token: nil)
    expect(queued.reload).to have_attributes(status: "suppressed", dispatch_started_at: nil)
    expect(attempted.reload.status).to eq("sent")
    expect(running.recipients.order(:id).pluck(:status)).to eq(%w[cancelled admitted])
  end

  it "paginates at 25/max100 and streams all filtered CSV rows without private payloads" do
    running = campaign(status: "completed", started_at: Time.current, stats: { "keep" => true })
    103.times do |index|
      person = contact(phone: "+86138#{format('%08d', index)}", name: "=SUM(#{index})")
      Sms::CampaignRecipient.create!(customer: customer, campaign: running, contact: person, phone_e164: person.phone_e164,
        status: "skipped", skip_reason: "consent_missing", contact_snapshot: { "name" => person.name }, vars: { "private" => "never-export" })
    end
    get "#{base}/contacts.json"
    expect(data.fetch("records").length).to eq(25)
    get "#{base}/contacts.json", params: { per_page: 500 }
    expect(data.fetch("records").length).to eq(100)
    expect(Sms::Campaigns::RefreshStats).not_to receive(:call)
    get "#{base}/campaigns/#{running.id}/report.csv", params: { status: "skipped", skip_reason: "consent_missing", per_page: 1, page: 2 }
    expect(response).to have_http_status(:ok), response.body
    rows = CSV.parse(response.body, headers: true)
    expect(rows.size).to eq(103)
    expect(rows.first["Name"]).to start_with("'=SUM(")
    expect(response.body).not_to include("never-export", "run_token", "credential")
    expect(running.reload.stats).to eq("keep" => true)
    get "#{base}/campaigns/#{running.id}/report.json", params: { q: "=SUM(10)", status: "skipped" }
    expect(data.fetch("records").size).to eq(1)
  end

  it "uses accessible shared Entity schemas but only synchronizes URL-tenant entries" do
    schema = [{ "name" => "Mobile", "name_slug" => "mobile", "type" => "String", "html_type" => "tel" }]
    shared = create(:entity, :shared, property_schema: schema.to_json)
    EntityEntry.create!(entity: shared, customer: customer, data: { "mobile" => "13800138000" }.to_json)
    other = create(:customer)
    EntityEntry.create!(entity: shared, customer: other, data: { "mobile" => "13800138001" }.to_json)
    attrs = { entity_id: shared.id, phone_field: "mobile", country_code: "CN", timezone: "Asia/Shanghai", attribute_map_json: "{}", after_entry_id: 0 }
    post "#{base}/contacts/entity_sync/preview.json", params: { sms_entity_sync: attrs }, as: :json
    expect(response).to have_http_status(:ok)
    expect(data.fetch("sync_result").fetch("scanned")).to eq(1)
    expect(Sms::Contact.count).to eq(0)
    attrs[:through_entry_id] = data.fetch("sync_result").fetch("through_entry_id")
    post "#{base}/contacts/entity_sync.json", params: { sms_entity_sync: attrs }, as: :json
    expect(response).to have_http_status(:ok)
    expect(Sms::Contact.pluck(:phone_e164, :consent_status)).to eq([["+8613800138000", "unknown"]])
    inaccessible = create(:entity, customer: other, property_schema: schema.to_json)
    post "#{base}/contacts/entity_sync/preview.json", params: { sms_entity_sync: attrs.merge(entity_id: inaccessible.id) }, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
