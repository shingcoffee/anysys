# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::SendActivityJob, type: :job do
  let(:customer) { create(:customer) }
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) { create(:email_credential, provider: "smtp") }
  let(:template) { create(:email_template, customer: customer, status: "active") }
  let(:list) { create(:email_list, customer: customer) }
  let(:campaign) do
    create(:email_send_activity, :processing, customer: customer,
           email_template: template, email_lists: [list])
  end

  before do
    2.times do |i|
      user = create(:user, customer: customer, email: "member#{i}@example.com")
      create(:email_list_membership, email_list: list, user: user)
    end
  end

  it "queues campaign messages for the list audience" do
    expect {
      described_class.perform_now(campaign.id)
    }.to change(Emails::Message, :count).by(2)

    campaign.reload
    expect(campaign.status).to eq("succeed")
  end

  it "re-enqueues in one minute without fan-out when the customer is throttled" do
    create(:email_message, customer: customer, message_type: "campaign", status: "queued", created_at: 30.seconds.ago)
    stub_const("#{described_class}::THROTTLE_PER_MINUTE", 1)

    freeze_time do
      expect { described_class.perform_now(campaign.id) }
        .to have_enqueued_job(described_class).with(campaign.id).at(1.minute.from_now)
    end

    expect(Emails::Message.where(email_send_activity_id: campaign.id)).to be_empty
  end

  it "re-enqueues until the next day when the daily cap is exhausted" do
    allow(described_class).to receive(:remaining_daily_cap).and_return(0)

    freeze_time do
      expect { described_class.perform_now(campaign.id) }
        .to have_enqueued_job(described_class).with(campaign.id)
        .at(Time.zone.now.tomorrow.beginning_of_day)
    end

    expect(campaign.reload.status).to eq("processing")
    expect(Emails::Message.where(email_send_activity_id: campaign.id)).to be_empty
  end

  it "does nothing when the campaign is not sending" do
    campaign.update!(status: "pending")
    expect {
      described_class.perform_now(campaign.id)
    }.not_to change(Emails::Message, :count)
  end

  it "does nothing when the Email module is disabled" do
    FeatureModules::CustomerAssignment.find_by!(
      customer: customer, feature_module: email_module
    ).update!(status: :suspended)
    expect {
      described_class.perform_now(campaign.id)
    }.not_to change(Emails::Message, :count)
    expect(campaign.reload.status).to eq("processing")
  end

  it "sends once when the recipient is on multiple selected lists" do
    user = create(:user, customer: customer, email: "once@example.com")
    list1 = create(:email_list, customer: customer)
    list2 = create(:email_list, customer: customer)
    create(:email_list_membership, email_list: list1, user: user)
    create(:email_list_membership, email_list: list2, user: user)
    multi_list_campaign = create(:email_send_activity, :processing, customer: customer,
                                  email_template: template, email_lists: [list1, list2])

    expect {
      described_class.perform_now(multi_list_campaign.id)
    }.to change { Emails::Message.where(email_send_activity_id: multi_list_campaign.id).count }.by(1)
  end
end
