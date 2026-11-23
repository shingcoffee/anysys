# frozen_string_literal: true

require_relative "sms_campaign_environment"
require_relative "../../../config/environment"
require "factory_bot"
FactoryBot.find_definitions unless FactoryBot.factories.registered?(:customer)

mode = ARGV.fetch(0)
input = JSON.parse(ARGV.fetch(1, "{}"))

case mode
when "create"
  uuid = SecureRandom.hex(8)
  # SKIP_AUTH resolves the canonical platform customer before tenant context.
  # Provision its reserved owner so fresh per-test tenants remain browsable.
  platform = Customer.find_or_create_by!(id: Authentication::User::PLATFORM_CUSTOMER_ID) do |record|
    record.name = "Browser platform"
    record.industry = :technology
    record.tier = :basic
  end
  unless Authentication::User.exists?(customer: platform, email: Authentication::User::PLATFORM_OWNER_EMAIL)
    FactoryBot.create(:user, :platform_owner, customer: platform)
  end
  customer = FactoryBot.create(:customer, name: "SMS browser #{uuid}")
  actor = FactoryBot.create(:user, :admin, customer: customer, email: "sms-browser-#{uuid}@example.test")
  mod = FeatureModules::Module.find_by!(key: "sms")
  mod.update!(status: :active)
  assignment = FeatureModules::CustomerAssignment.find_or_initialize_by(customer: customer, feature_module: mod)
  assignment.assign_attributes(status: :active, configuration: { daily_send_cap: 100 }.to_json)
  assignment.save!
  credential = Sms::Credential.find_or_initialize_by(provider: "aliyun", mode: "sandbox")
  credential.assign_attributes(status: "active", access_key_id: "E2E_LOCAL_ONLY", access_key_secret: "E2E_LOCAL_ONLY",
                               config: { "sign_name" => "LocalUI", "region" => "cn-hangzhou", "sender_rate_per_second" => 1 })
  credential.save!
  template = FactoryBot.create(:sms_template, key: "browser_offer_#{uuid}", purpose: "marketing",
    variables: %w[name opt_out_url], description: "Browser approved offer #{uuid}", body_template: "Hi {{name}} {{opt_out_url}}")
  puts JSON.generate(customer_id: customer.id, actor_id: actor.id, template_id: template.id, template_label: template.description,
                     contact_name: "Contact #{uuid}", segment_name: "Segment #{uuid}", campaign_name: "Campaign #{uuid}")
when "state"
  customer = Customer.find(input.fetch("customer_id"))
  abort "Fixture ownership mismatch" unless customer.name.start_with?("SMS browser ")
  campaign = Sms::Campaign.where(customer: customer).order(:id).last
  puts JSON.generate(contacts: Sms::Contact.where(customer: customer).pluck(:name, :consent_status),
                     campaign_id: campaign&.id, campaign_name: campaign&.name, campaign_status: campaign&.status,
                     messages: Sms::Message.where(customer: customer).count,
                     recipients: Sms::CampaignRecipient.where(customer: customer).count,
                     events: Sms::ConsentEvent.where(customer: customer).count)
when "entity"
  customer = Customer.find(input.fetch("customer_id"))
  abort "Fixture ownership mismatch" unless customer.name.start_with?("SMS browser ")
  uuid = SecureRandom.hex(8)
  entity = FactoryBot.create(:entity, customer: customer, name: "Browser people #{uuid}", property_schema: [
    { "name" => "Mobile", "name_slug" => "mobile", "type" => "String", "html_type" => "tel" },
    { "name" => "Full name", "name_slug" => "full_name", "type" => "String", "html_type" => "text" }
  ].to_json)
  EntityEntry.create!(customer: customer, entity: entity, data: { "mobile" => "13800138001", "full_name" => "Entity contact #{uuid}" }.to_json)
  puts JSON.generate(entity_id: entity.id, entity_label: entity.display_label, name: "Entity contact #{uuid}")
when "unsubscribe"
  customer = Customer.find(input.fetch("customer_id"))
  abort "Fixture ownership mismatch" unless customer.name.start_with?("SMS browser ")
  contact = Sms::Contact.where(customer: customer).sole
  puts JSON.generate(token: Sms::Campaigns::Unsubscribe.token_for(customer: customer, contact: contact, phone_e164: contact.phone_e164))
else
  abort "Unknown SMS UI fixture mode"
end
