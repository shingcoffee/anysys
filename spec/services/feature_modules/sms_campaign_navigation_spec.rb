# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SMS campaign navigation and access points" do
  it "links the module entry to campaigns and groups audience surfaces under one sidebar entry" do
    customer = create(:customer)
    expect(FeatureModules::Sms::Registration.entry_path_for(customer)).to eq("/#{customer.id}/admin/modules/sms/campaigns")
    expect(FeatureModules::Sms::Registration.sidebar_contributions(nil).fetch(:entries)).to eq([])

    entries = FeatureModules::Sms::Registration.sidebar_contributions(double(current_customer: customer)).fetch(:entries)
    expect(entries.map(&:entry_key)).to eq(%w[campaigns audience messages])
    audience = entries.find { |entry| entry.entry_key == "audience" }
    expect(audience.path.call(customer.id)).to eq("/#{customer.id}/admin/modules/sms/contacts")
    expect(audience.match_prefix).to eq(%W[
      /#{customer.id}/admin/modules/sms/contacts
      /#{customer.id}/admin/modules/sms/segments
      /#{customer.id}/admin/modules/sms/opt_outs
    ])
  end

  it "registers the route actions in the access catalog with translated labels" do
    provider = AccessPoints::RouteProvider.new
    %w[en zh-CN].each do |locale|
      I18n.with_locale(locale) do
        descriptors = provider.call(customer_id: 81721200)
        contacts = descriptors.find { |descriptor| descriptor.subject_key == "admin/modules/sms/contacts" }
        consent = descriptors.find { |descriptor| descriptor.subject_key == "admin/modules/sms/consent_events" }
        expect(contacts.actions).to match_array(%i[read create update destroy])
        expect(consent.actions).to eq([:create])
        expect(contacts.label).to eq(I18n.t("sms_campaign_http.navigation.contacts"))
        sms = descriptors.select { |descriptor| AccessPoints::SmsRouteLabels.key_for(descriptor.subject_key) }
        expect(sms.size).to eq(8)
        expect(sms.map(&:label).uniq.size).to eq(8)
        sms.each do |descriptor|
          label = Admin::Settings::Modules::Authentication::GrantRouteLabel.new(descriptor.subject_key).label
          expect(label).to end_with(" — #{descriptor.label}")
          expect(label).not_to include(I18n.t("settings_people.grant_resources.other"))
        end
      end
    end
  end
end
