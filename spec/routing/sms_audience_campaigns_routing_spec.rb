# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS audience and campaign routes", type: :routing do
  let(:cid) { "12345678" }
  let(:base) { "/#{cid}/admin/modules/sms" }

  it "routes static Entity sync paths before contact IDs" do
    expect(get: "#{base}/contacts/entity_sync/new").to route_to("admin/modules/sms/entity_syncs#new", customer_id: cid)
    expect(post: "#{base}/contacts/entity_sync/preview").to route_to("admin/modules/sms/entity_syncs#preview", customer_id: cid)
    expect(post: "#{base}/contacts/entity_sync").to route_to("admin/modules/sms/entity_syncs#create", customer_id: cid)
  end

  it "provides the frozen helpers and independent preview/action verbs" do
    helpers = Rails.application.routes.url_helpers
    expect(helpers.admin_modules_sms_new_contacts_entity_sync_path(cid)).to eq("#{base}/contacts/entity_sync/new")
    expect(helpers.admin_modules_sms_preview_contacts_entity_sync_path(cid)).to eq("#{base}/contacts/entity_sync/preview")
    expect(helpers.admin_modules_sms_contacts_entity_sync_path(cid)).to eq("#{base}/contacts/entity_sync")
    expect(helpers.admin_modules_sms_new_contact_path(cid)).to eq("#{base}/contacts/new")
    expect(helpers.admin_modules_sms_edit_contact_path(cid, 7)).to eq("#{base}/contacts/7/edit")
    expect(helpers.admin_modules_sms_new_segment_path(cid)).to eq("#{base}/segments/new")
    expect(helpers.admin_modules_sms_edit_segment_path(cid, 7)).to eq("#{base}/segments/7/edit")
    expect(helpers.admin_modules_sms_new_campaign_path(cid)).to eq("#{base}/campaigns/new")
    expect(helpers.admin_modules_sms_edit_campaign_path(cid, 8)).to eq("#{base}/campaigns/8/edit")
    expect(helpers.admin_modules_sms_contact_consent_events_path(cid, 7)).to eq("#{base}/contacts/7/consent_events")
    expect(helpers.admin_modules_sms_preview_segments_path(cid)).to eq("#{base}/segments/preview")
    expect(helpers.admin_modules_sms_preview_segment_path(cid, 7)).to eq("#{base}/segments/7/preview")
    expect(post: "#{base}/segments/7/preview").to route_to("admin/modules/sms/segments#preview", customer_id: cid, id: "7")
    expect(helpers.admin_modules_sms_preview_campaigns_path(cid)).to eq("#{base}/campaigns/preview")
    expect(helpers.admin_modules_sms_preview_campaign_path(cid, 8)).to eq("#{base}/campaigns/8/preview")
    expect(helpers.admin_modules_sms_launch_campaign_path(cid, 8)).to eq("#{base}/campaigns/8/launch")
    expect(helpers.admin_modules_sms_cancel_campaign_path(cid, 8)).to eq("#{base}/campaigns/8/cancel")
    expect(helpers.admin_modules_sms_campaign_report_path(cid, 8, format: :csv)).to eq("#{base}/campaigns/8/report.csv")
    expect(post: "#{base}/campaigns/8/launch").to route_to("admin/modules/sms/campaign_launches#create", customer_id: cid, id: "8")
    expect(post: "#{base}/campaigns/8/cancel").to route_to("admin/modules/sms/campaign_cancellations#create", customer_id: cid, id: "8")
    expect(get: "#{base}/campaigns/8/report.csv").to route_to("admin/modules/sms/campaign_reports#show", customer_id: cid, campaign_id: "8", format: "csv")
  end

  it "shares the public confirmation helper between GET and POST and has no evidence edit route" do
    expect(Rails.application.routes.url_helpers.sms_unsubscribe_path("signed-token")).to eq("/sms/unsubscribes/signed-token")
    expect(get: "/sms/unsubscribes/signed-token").to route_to("sms/unsubscribes#show", token: "signed-token")
    expect(post: "/sms/unsubscribes/signed-token").to route_to("sms/unsubscribes#create", token: "signed-token")
    expect(patch: "#{base}/contacts/7/consent_events/1").not_to be_routable
  end
end
