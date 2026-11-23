# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS native form HTTP integration", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:base) { "/#{customer.id}/admin/modules/sms" }

  before do
    sms = FeatureModules::Module.find_by(key: "sms") || create(:feature_module, key: "sms", name: "SMS")
    sms.update!(status: :active)
    create(:customer_feature_module, customer: customer, feature_module: sms)
    sign_in admin
  end

  it "renders each new surface with its required assign hash and scoped navigation" do
    contact = Sms::Contact.create!(customer: customer, phone_e164: "+8613800138000")
    segment = Sms::Audience::Segment.create!(customer: customer, name: "Segment")
    campaign = Sms::Campaign.create!(customer: customer, created_by: admin, name: "Draft")
    paths = %W[contacts contacts/new contacts/#{contact.id} contacts/#{contact.id}/edit
               contacts/entity_sync/new segments segments/new segments/#{segment.id} segments/#{segment.id}/edit
               campaigns campaigns/new campaigns/#{campaign.id} campaigns/#{campaign.id}/edit campaigns/#{campaign.id}/report]
    paths.each do |suffix|
      get "#{base}/#{suffix}"
      expect(response).to have_http_status(:ok), "#{suffix}: #{Nokogiri::HTML(response.body).css('.exception-message').text}"
    end
  end

  it "retains malformed JSON and the posted form fields in a 422 HTML rerender" do
    post "#{base}/campaigns/preview", params: { commit: "preview", sms_campaign: { name: "Unsaved & retained", variable_map_json: '{"broken":' } }
    expect(response).to have_http_status(:unprocessable_entity)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[name="sms_campaign[name]"]')["value"]).to eq("Unsaved & retained")
    # Rails emits the HTML textarea's leading newline, which browsers discard.
    expect(document.at_css('textarea[name="sms_campaign[variable_map_json]"]').text.delete_prefix("\n")).to eq('{"broken":')
    expect(Sms::Campaign.count).to eq(0)
    expect(Sms::Message.count).to eq(0)
    post "#{base}/contacts", params: { sms_contact: { phone: "13800138000", custom_attributes_json: "not-json" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Nokogiri::HTML(response.body).at_css('textarea[name="sms_contact[custom_attributes_json]"]').text.delete_prefix("\n")).to eq("not-json")
    expect(Sms::Contact.count).to eq(0)
  end

  it "separates native POST preview from PATCH draft save and excludes sample metadata from persistence" do
    record = Sms::Campaign.create!(customer: customer, created_by: admin, name: "Saved")
    sample = Sms::Contact.create!(customer: customer, phone_e164: "+8613800138000")
    get "#{base}/campaigns/#{record.id}/edit"
    document = Nokogiri::HTML(response.body)
    form = document.at_css('form[action="' + "#{base}/campaigns/#{record.id}" + '"]')
    expect(form).to be_present
    expect(form.css('input[name="_method"]')).to be_empty
    expect(form.at_css('button[name="_method"]')["value"]).to eq("patch")
    expect(form.at_css('button[value="preview"]')["formaction"]).to eq("#{base}/campaigns/#{record.id}/preview")
    post "#{base}/campaigns/#{record.id}/preview", params: { commit: "preview", preview_contact_id: sample.id,
      sms_campaign: { name: "Unsaved preview", variable_map_json: "{}", lock_version: record.lock_version } }
    expect(response).to have_http_status(:ok)
    expect(record.reload.name).to eq("Saved")
    post "#{base}/campaigns/#{record.id}", params: { _method: "patch", preview_contact_id: sample.id,
      sms_campaign: { name: "Saved update", variable_map_json: "{}", lock_version: record.lock_version } }
    expect(response).to have_http_status(:see_other)
    expect(record.reload).to have_attributes(name: "Saved update", status: "draft")
    expect(record.attributes).not_to have_key("preview_contact_id")
    expect(Sms::Message.count).to eq(0)
  end

  it "rerenders the contact detail and consent form with evidence validation errors" do
    contact = Sms::Contact.create!(customer: customer, phone_e164: "+8613800138000")
    post "#{base}/contacts/#{contact.id}/consent_events", params: { sms_consent_event: { action: "granted", occurred_at: 1.minute.ago.iso8601,
      reference: "Retained reference", statement: "", event_key: SecureRandom.uuid } }
    expect(response).to have_http_status(:unprocessable_entity)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('input[name="sms_consent_event[reference]"]')["value"]).to eq("Retained reference")
    expect(Sms::ConsentEvent.count).to eq(0)
  end

  it "preserves the edited segment through Preview and updates it through the returned Save action" do
    segment = Sms::Audience::Segment.create!(customer: customer, name: "Original", description: "Saved description")
    rules = { "type" => "group", "conditions" => [{ "field" => "country_code", "operator" => "equals", "value" => "CN" }], "joins" => [] }
    version = segment.lock_version
    get "#{base}/segments/#{segment.id}/edit"
    edit_form = Nokogiri::HTML(response.body).at_css('form[action="' + "#{base}/segments/#{segment.id}" + '"]')
    expect(edit_form.at_css('button[value="preview"]')["formaction"]).to eq("#{base}/segments/#{segment.id}/preview")

    submitted = { name: "Previewed rename", description: "Unsaved description", segment_rules_json: JSON.generate(rules), lock_version: version }
    counts = [Sms::Audience::Segment.count, Sms::Message.count, Sms::CampaignRecipient.count, enqueued_jobs.size]
    post edit_form.at_css('button[value="preview"]')["formaction"], params: { sms_segment: submitted }
    expect(response).to have_http_status(:ok)
    expect(segment.reload).to have_attributes(name: "Original", description: "Saved description", lock_version: version)
    expect([Sms::Audience::Segment.count, Sms::Message.count, Sms::CampaignRecipient.count, enqueued_jobs.size]).to eq(counts)

    preview_form = Nokogiri::HTML(response.body).at_css('form[action="' + "#{base}/segments/#{segment.id}" + '"]')
    expect(preview_form).to be_present
    expect(preview_form.at_css('input[name="sms_segment[name]"]')["value"]).to eq(submitted[:name])
    expect(preview_form.at_css('input[name="sms_segment[lock_version]"]')["value"]).to eq(version.to_s)
    expect(JSON.parse(preview_form.at_css('input[name="sms_segment[segment_rules_json]"]')["value"])).to eq(rules)
    expect(preview_form.css('input[name="_method"]')).to be_empty
    save = preview_form.at_css('button[name="_method"]')
    expect(save["value"]).to eq("patch")
    post save["formaction"], params: { _method: save["value"], sms_segment: submitted }
    expect(response).to have_http_status(:see_other)
    expect(segment.reload).to have_attributes(name: submitted[:name], description: submitted[:description], segment_rules: rules)
    expect(Sms::Audience::Segment.where(customer_id: customer.id).count).to eq(1)
  end

  it "retains segment identity and the original edit version on invalid and stale previews" do
    segment = Sms::Audience::Segment.create!(customer: customer, name: "Original")
    old_version = segment.lock_version
    segment.update!(description: "Concurrent change")
    post "#{base}/segments/#{segment.id}/preview", params: { sms_segment: { name: "Pending rename", segment_rules_json: "{invalid", lock_version: old_version } }
    expect(response).to have_http_status(:unprocessable_entity)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('form[action="' + "#{base}/segments/#{segment.id}" + '"]')).to be_present
    expect(document.at_css('input[name="sms_segment[lock_version]"]')["value"]).to eq(old_version.to_s)
    expect(document.at_css('textarea[name="sms_segment[segment_rules_json]"]').text.delete_prefix("\n")).to eq("{invalid")

    post "#{base}/segments/#{segment.id}/preview", params: { sms_segment: { name: "Pending rename", segment_rules_json: "{}", lock_version: old_version } }
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('input[name="sms_segment[lock_version]"]')["value"]).to eq(old_version.to_s)
    post "#{base}/segments/#{segment.id}", params: { _method: "patch", sms_segment: { name: "Pending rename", segment_rules_json: "{}", lock_version: old_version } }
    expect(response).to have_http_status(:conflict)
    expect(segment.reload).to have_attributes(name: "Original", description: "Concurrent change")
    expect(Sms::Audience::Segment.where(customer_id: customer.id).count).to eq(1)
  end

  it "rejects inaccessible member-preview identities without falling back to a new segment" do
    foreign = Sms::Audience::Segment.create!(customer: create(:customer), name: "Other tenant")
    sign_in find_or_create_platform_owner
    [foreign.id, "999999999999999999", "invalid"].each do |id|
      post "#{base}/segments/#{id}/preview.json", params: { sms_segment: { name: "Do not create", segment_rules_json: "{}" } }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
    end
    expect(Sms::Audience::Segment.where(customer_id: customer.id)).not_to exist
    expect(foreign.reload.name).to eq("Other tenant")
  end

  it "continues to preview new segments through the collection action" do
    post "#{base}/segments/preview", params: { sms_segment: { name: "New segment", segment_rules_json: "{}", lock_version: 0 } }
    expect(response).to have_http_status(:ok)
    form = Nokogiri::HTML(response.body).at_css('form[action="' + "#{base}/segments" + '"]')
    expect(form.at_css('button[value="preview"]')["formaction"]).to eq("#{base}/segments/preview")
    expect(form.css('button[name="_method"], input[name="_method"]')).to be_empty
    expect(Sms::Audience::Segment.where(customer_id: customer.id)).not_to exist
  end
end
