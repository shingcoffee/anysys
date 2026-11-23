# frozen_string_literal: true

RSpec.shared_context "SMS campaign engine" do
  let(:customer) { create(:customer) }
  let(:actor) { create(:user, :admin, customer: customer) }
  let!(:credential) { create(:sms_credential) }
  let!(:template) do
    create(:sms_template, purpose: "marketing", variables: %w[name opt_out_url],
      body_template: "Hello {{name}}. Unsubscribe: {{opt_out_url}}")
  end
  let!(:contact) do
    Sms::Contact.create!(customer: customer, phone_e164: "+8613800138000", name: "Alice", consent_status: "granted")
  end
  let(:mapping) do
    { "name" => { "source" => "field", "field" => "name" },
      "opt_out_url" => { "source" => "field", "field" => "unsubscribe_url" } }
  end

  before do
    travel_to(Time.utc(2026, 10, 13, 2))
    enable_module!("sms", customer, name: "SMS")
    clear_enqueued_jobs
    allow_any_instance_of(Sms::Adapters::Aliyun).to receive(:send_message)
      .and_return(vendor_message_id: "accepted-id", raw: {})
  end

  after do
    clear_enqueued_jobs
    Current.reset
    travel_back
  end

  def save_campaign(**attrs)
    result = Sms::Campaigns::Save.call(customer: customer, actor: actor, attributes:
      { name: "Autumn offer", template_id: template.id, variable_map: mapping }.merge(attrs))
    expect(result.errors).to eq({})
    expect(result).to be_success
    result.value
  end

  def launch_campaign(campaign = save_campaign)
    preview = Sms::Campaigns::Preview.call(customer: customer, actor: actor, campaign: campaign)
    expect(preview.errors).to eq({})
    expect(preview.value[:blockers]).to eq([])
    version = campaign.lock_version
    result = Sms::Campaigns::Launch.call(customer: customer, actor: actor, campaign: campaign,
      lock_version: version, review_token: preview.value[:review_token])
    expect(result.errors).to eq({})
    expect(result).to be_success
    result.value
  end

  def claim_campaign(campaign)
    Sms::Campaigns::SchedulerJob.new.perform
    campaign.reload
    expect(campaign.run_token).to be_present
    campaign.run_token
  end

  def run_campaign(campaign, token: nil, **options)
    token ||= campaign.run_token || claim_campaign(campaign)
    Sms::Campaigns::Run.call(customer: customer, campaign: campaign, run_token: token, **options)
  end
end
