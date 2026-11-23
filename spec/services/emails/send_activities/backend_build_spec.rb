# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::SendActivities::Build do
  let(:customer) { create(:customer) }
  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) { create(:email_credential, mode: "sandbox") }
  let(:campaign) { create(:email_send_activity, customer: customer, scheduled_at: 1.day.from_now) }

  def submit(record = campaign, **attributes)
    described_class.call(record, ActionController::Parameters.new(email_send_activity: attributes))
  end

  it "does not persist replacement lists when parent validation fails" do
    original = campaign.email_list_ids
    replacement = create(:email_list, customer: customer)

    result = submit(name: "", email_list_ids: [replacement.id])

    expect(result[:success]).to be(false)
    expect(campaign.errors[:name]).to be_present
    expect(Emails::SendActivities::SendActivity.find(campaign.id).email_list_ids).to eq(original)
  end

  it "rolls back changed joins if the actual parent save fails after contract validation" do
    original = campaign.email_list_ids
    replacement = create(:email_list, customer: customer)
    allow(campaign).to receive(:save).and_return(false)

    result = submit(email_list_ids: [replacement.id])

    expect(result[:success]).to be(false)
    expect(Emails::SendActivities::SendActivity.find(campaign.id).email_list_ids).to eq(original)
  end

  it "returns a validation error for eleven lists before association callbacks execute" do
    lists = create_list(:email_list, 11, customer: customer)
    original = campaign.email_list_ids

    result = nil
    expect { result = submit(email_list_ids: lists.map(&:id)) }.not_to raise_error

    expect(result[:success]).to be(false)
    expect(campaign.errors[:email_lists]).to be_present
    expect(Emails::SendActivities::SendActivity.find(campaign.id).email_list_ids).to eq(original)
  end

  it "rejects missing, inactive, and foreign templates" do
    candidates = [-1, create(:email_template, :draft, customer: customer).id,
                  create(:email_template, customer: create(:customer)).id]
    original = campaign.email_template_id
    candidates.each do |id|
      fresh = Emails::SendActivities::SendActivity.find(campaign.id)
      result = submit(fresh, email_template_id: id)
      expect(result[:success]).to be(false)
      expect(fresh.errors[:email_template_id]).to be_present
    end
    expect(campaign.reload.email_template_id).to eq(original)
  end

  it "rejects an edit whose stale pending copy has since been claimed by the scheduler" do
    stale = campaign
    expect(Emails::SendActivities::SendActivity.claim!(stale.id)).to be(true)

    result = submit(stale, name: "Should not apply")

    expect(result[:success]).to be(false)
    expect(campaign.reload.name).not_to eq("Should not apply")
    expect(campaign.status).to eq("processing")
  end

  it "rejects destruction from a stale pending copy after a claim" do
    stale = campaign
    Emails::SendActivities::SendActivity.claim!(stale.id)

    expect(stale.destroy).to be(false)
    expect(Emails::SendActivities::SendActivity.exists?(stale.id)).to be(true)
  end

  it "rechecks a changed future schedule on scheduler-only starts" do
    stale = campaign
    stale.update!(scheduled_at: 1.minute.ago)
    Emails::SendActivities::SendActivity.find(stale.id).update!(scheduled_at: 1.day.from_now)

    expect(Emails::SendActivities::StartSendActivity.call(stale, due_only: true)).to be(false)
    expect(campaign.reload.status).to eq("pending")
  end

  it "does not auto-start if another edit reschedules after the build commits" do
    campaign.update!(scheduled_at: 1.minute.ago)
    allow(Emails::SendActivities::StartSendActivity).to receive(:call).and_wrap_original do |method, activity, **arguments|
      Emails::SendActivities::SendActivity.find(activity.id).update_columns(scheduled_at: 1.day.from_now)
      method.call(activity, **arguments)
    end

    expect { submit(name: "Rescheduled") }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
    expect(campaign.reload.status).to eq("pending")
    expect(campaign.scheduled_at).to be > Time.current
  end

  it "rolls back the start claim if scheduling the next occurrence fails" do
    campaign.update!(recurrence_rule: "FREQ=DAILY", scheduled_at: 1.minute.ago)
    allow(Emails::SendActivities::StartSendActivity).to receive(:schedule_next_occurrence).and_raise(ActiveRecord::RecordInvalid.new(campaign))

    expect { Emails::SendActivities::StartSendActivity.call(campaign) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.reload.status).to eq("pending")
  end

  it "rejects unsupported campaign transport before saving a new campaign or starting its fan-out" do
    credential.update!(status: "disabled")
    create(:email_credential, provider: "aliyun", mode: "sandbox", username: nil,
           config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })
    template = create(:email_template, customer: customer)
    list = create(:email_list, customer: customer)
    draft = Emails::SendActivities::SendActivity.new(customer: customer)

    expect {
      result = submit(draft, name: "Unsupported", email_template_id: template.id, email_list_ids: [list.id],
                      timezone: "UTC", send_timing: "now")
      expect(result[:success]).to be(false)
      expect(draft.errors[:base]).to be_present
    }.not_to change(Emails::SendActivities::SendActivity, :count)
    expect(Emails::SendActivities::SendActivityJob).not_to have_been_enqueued
  end
end
