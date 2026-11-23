# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS segment and draft deletion HTTP", type: :request do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let(:base) { "/#{customer.id}/admin/modules/sms" }

  before do
    sms = FeatureModules::Module.find_by(key: "sms") || create(:feature_module, key: "sms", name: "SMS")
    sms.update!(status: :active)
    create(:customer_feature_module, customer: customer, feature_module: sms)
    sign_in actor
  end

  it "redirects after deleting an unused segment and returns the deleted draft ID as JSON" do
    segment = create(:sms_segment, customer: customer)
    campaign = create(:sms_campaign, customer: customer, created_by: actor)
    delete "#{base}/segments/#{segment.id}"
    expect(response).to redirect_to("#{base}/segments")
    expect(response).to have_http_status(:see_other)
    expect(Sms::Audience::Segment.exists?(segment.id)).to be(false)
    delete "#{base}/campaigns/#{campaign.id}.json"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("data" => { "id" => campaign.id })
    expect(Sms::Campaign.exists?(campaign.id)).to be(false)
  end

  it "keeps draft-referenced segments and returns the same conflict in both locales" do
    segment = create(:sms_segment, customer: customer)
    campaign = create(:sms_campaign, customer: customer, created_by: actor, segment: segment)
    %w[en zh-CN].each do |locale|
      delete "#{base}/segments/#{segment.id}.json", params: { locale: locale }
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq("error" => { "code" => "segment_in_use", "errors" => {
        "base" => [I18n.t("sms_campaign_http.errors.segment_in_use", locale: locale)] } })
    end
    delete "#{base}/segments/#{segment.id}"
    expect(response).to have_http_status(:conflict)
    expect(campaign.reload.segment_id).to eq(segment.id)
    expect(segment.reload).to be_persisted
  end

  it "renders campaign detail conflicts for retained states and drafts with recipients" do
    records = %w[scheduled running completed cancelled failed].map do |status|
      create(:sms_campaign, customer: customer, created_by: actor, status: status)
    end
    draft = create(:sms_campaign, customer: customer, created_by: actor)
    create(:sms_campaign_recipient, campaign: draft, customer: customer)
    (records + [draft]).each do |campaign|
      delete "#{base}/campaigns/#{campaign.id}"
      expect(response).to have_http_status(:conflict)
      expect(response.body).to include(I18n.t("sms_campaign_http.errors.not_draft"))
      expect(campaign.reload).to be_persisted
    end
  end

  it "lets the pinned owner delete within the URL tenant but keeps foreign segment and campaign IDs inaccessible" do
    owner = find_or_create_platform_owner
    sign_in owner
    segment = create(:sms_segment, customer: customer)
    draft = create(:sms_campaign, customer: customer, created_by: actor)
    foreign_segment = create(:sms_segment)
    foreign_draft = create(:sms_campaign)
    [["segments", foreign_segment], ["campaigns", foreign_draft]].each do |kind, record|
      delete "#{base}/#{kind}/#{record.id}.json"
      expect(response).to have_http_status(:not_found)
      expect(record.reload).to be_persisted
    end
    [["segments", segment], ["campaigns", draft]].each do |kind, record|
      delete "#{base}/#{kind}/#{record.id}.json"
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("data", "id")).to eq(record.id)
    end
  end

  it "rejects editable/protected deletion parameters before any persistence" do
    segment = create(:sms_segment, customer: customer)
    draft = create(:sms_campaign, customer: customer, created_by: actor)
    [["segments", segment], ["campaigns", draft]].each do |kind, record|
      delete "#{base}/#{kind}/#{record.id}.json", params: { customer_id: customer.id, status: "draft" }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(record.reload).to be_persisted
    end
  end
end
