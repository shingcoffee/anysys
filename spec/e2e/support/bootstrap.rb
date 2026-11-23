# frozen_string_literal: true

# May be launched directly or by helpers/bootstrap.js. Assert configuration
# before application initialization, whose hooks can already write catalog rows.
require "bundler/setup"
require "pathname"
require "json"
root = Pathname.new(__dir__).join("../../..").realpath
expected = Pathname.new(ENV.fetch("E2E_DATABASE_PATH")).expand_path(root)
abort "Dedicated app-local E2E database required" unless expected.dirname == root.join("storage").realpath &&
  expected.basename.to_s.match?(/\A(?:browser|e2e)[\w.-]*\.sqlite3\z/) &&
  (!expected.exist? || expected.realpath == expected)
abort "Database URL mismatch" unless ENV.fetch("DATABASE_URL") == "sqlite3:#{expected}"
abort "E2E environment required" unless %w[development test].include?(ENV.fetch("RAILS_ENV"))
abort "Use the local HTTP provider" if ENV["E2E_STUB_ASSISTANT"] == "1"
require_relative "../../../config/application"
ActiveRecord::Base.configurations = Rails.application.config.database_configuration
config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
abort "E2E database configuration mismatch" unless config.adapter == "sqlite3" &&
  Pathname.new(config.database).expand_path(root) == expected
abort "Prepare the isolated database first" unless expected.file?
require_relative "../../../config/environment"

# Real models, callbacks, versions and provisioners produce the fixture.
require "factory_bot"
require_relative "../../../app/services/ai_assistant/providers/openai_whisper"
FactoryBot.definition_file_paths = [Rails.root.join("spec/factories")]
FactoryBot.reload

Billing::StandardPlans.seed!
# Register through the same public entry point used by the Rails initializer.
Rails.root.glob("app/services/feature_modules/*/registration.rb").each do |path|
  "FeatureModules::#{path.parent.basename.to_s.camelize}::Registration".constantize.register!
end
FeatureModules::Module.find_each { |feature| feature.update!(status: :active) }
customer = Customer.find_or_create_by!(id: 81721200) do |row|
  row.name = "Browser verification"
  row.industry = Customer.industries.keys.first
end
%w[authentication website ai_assistant email sms captcha payment].each do |key|
  feature = FeatureModules::Module.find_by!(key: key)
  assignment = FeatureModules::CustomerAssignment.find_or_initialize_by(customer: customer, feature_module: feature)
  assignment.update!(status: :active, enabled_at: assignment.enabled_at || Time.current)
  feature.registration_class.provision!(customer)
end
owner = customer.users.find_by!(email: "lingercoffee@gmail.com")
abort "Pinned platform owner required" unless owner.platform_owner?

# No existing encrypted key is read or reused. Official provider availability
# checks see a valid dummy row; SDK HTTP endpoints are set by the test launcher.
settings = AiAssistant::ProviderSettings.for_provider("openai_whisper")
settings.update!(api_key: "e2e-local-dummy-key", config: {
  "model" => "whisper-1", "chat_model" => "gpt-4o-mini"
}.to_json)
settings.activate_for!(:generation)
settings.activate_for!(:transcribe)
abort "Provider readiness failed" unless AiAssistant::ProviderSettings::JOBS.all? { |job| AiAssistant::ProviderSettings.active_for(job)&.id == settings.id }
Emails::PlatformTokenSeeds.ensure!

Current.with_customer(customer) do
  EntityDomain.find_by_name(customer.id, "Academics") || FactoryBot.create(:entity_domain, customer: customer, name: "Academics")
  entity = Entity.find_by(customer: customer, name: "BrowserContact") || FactoryBot.create(
    :entity, customer: customer, name: "BrowserContact", property_schema: [
      { name: "First name", name_slug: "first_name", type: "String", html_type: "text" },
      { name: "Status", name_slug: "status", type: "String", html_type: "text" },
      { name: "Note", name_slug: "note", type: "String", html_type: "text" }
    ].to_json
  )
  token = Emails::TemplateToken.find_or_initialize_by(customer: customer, label: "First name")
  token.update!(source_type: Emails::TemplateToken::SOURCE_ENTITY, entity: entity, attribute_slug: "first_name")
  abort "First-name token is not accessible" unless Emails::TemplateToken.accessible_for(customer.id).exists?(token.id) && token.valid?
  Entity.find_by(customer: customer, name: "employee") || FactoryBot.create(:entity, :with_name_status_schema, customer: customer, name: "employee")
  Entity.find_by(customer: customer, name: "invoice") || FactoryBot.create(:entity, :with_name_status_schema, customer: customer, name: "invoice")
  # More than eight mention candidates, including spaced flowchart names.
  9.times do |index|
    name = "Browser Flow #{index + 1}"
    Flowchart.find_by(customer: customer, name: name) || FactoryBot.create(:flowchart, :simple, :draft, customer: customer, name: name)
  end
  flowchart = Flowchart.find_by!(customer: customer, name: "Browser Flow 1")
  page = Page.find_by(customer: customer, name: "Browser drag fields") || FactoryBot.create(
    :page, customer: customer, entity: entity, name: "Browser drag fields", configuration: {
      pages: [{ id: "page_1", name: "Browser fields", order: 1, fields: entity.property_schema_json.map do |attribute|
        { id: "field_#{attribute.fetch('name_slug')}", name: attribute.fetch("name_slug"), label: attribute.fetch("name"), type: "text", entity_attribute: attribute.fetch("name_slug") }
      end }]
    }.to_json
  )
  2.times do |index|
    conversation = AiAssistant::Conversation.find_or_create_by!(customer: customer, user: owner, title: "Browser fixture #{index + 1}")
    if conversation.messages.empty?
      conversation.messages.create!(customer: customer, role: "user", body: "Browser fixture question", status: "complete")
      conversation.messages.create!(customer: customer, role: "assistant", body: "Browser fixture response", status: "complete")
    end
  end
  puts({ database: ActiveRecord::Base.connection_db_config.database,
         PAGE_EDIT_PATH: "/81721200/admin/maintenance/pages/#{page.id}/edit",
          FLOWCHART_EDIT_PATH: "/81721200/admin/maintenance/flowcharts/#{flowchart.id}/edit",
          ENTITY_EDIT_PATH: "/81721200/admin/maintenance/entities/#{entity.id}/edit",
          E2E_ASSISTANT_CONVERSATION_ID: AiAssistant::Conversation.find_by!(customer: customer, user: owner, title: "Browser fixture 1").id,
          token_id: token.id, generation_provider_available: true, transcribe_provider_available: true }.to_json)
end
