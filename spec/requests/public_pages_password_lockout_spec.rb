# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page durable password lockout", type: :request do
  self.use_transactional_tests = false

  let(:customer) { create(:customer) }
  let(:user) { create(:user, :member, customer: customer) }
  let(:entity) do
    schema = %w[email password fail_after continue_after].map { |key| { "name_slug" => key } }
    create(:entity, customer: customer, property_schema: schema.to_json)
  end
  let(:page) do
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, entity: entity, launched: true,
             configuration: { metadata: { entity_id: entity.id }, fields: [] }.to_json)
    end
  end
  let(:flowchart) do
    method = CodeGenerators::ElementTypes::Process::Security::AuthenticateGenerator.new(
      { "config" => { "authMethod" => "password", "credentialSource" => "params", "sourceVariable" => "password" } }, {}
    ).generate_step_method
    bind_page_flowchart(page, code: <<~RUBY)
      class DurablePasswordSubmissionActivity < Trailblazer::Activity::Railway
        step :prepare_business_data
        step :check_password
        step :finish
        step :save_record
        #{method}
        def prepare_business_data(ctx, **)
          ctx[:user] = Authentication::User.find_by(email: ctx[:params]["email"], customer_id: ctx[:customer_id])
          ctx[:user].first_name = "Unsaved business change" if ctx[:user]
          true
        end
        def check_password(ctx, **)
          accepted = authenticate(ctx)
          ctx[:params]["continue_after"] == "yes" || accepted
        end
        def finish(ctx, **)
          ctx[:params]["fail_after"] != "yes"
        end
        def save_record(ctx, **)
          ctx[:model].save
        end
      end
    RUBY
  end
  let(:url) { "/#{customer.id}/page/#{page.public_uuid}" }

  before do
    raise "This spec requires real request transactions" if ActiveRecord::Base.connection.transaction_open?
    user
    flowchart
  end

  after do
    page.destroy!
    EntityEntry.where(entity: entity).destroy_all
    flowchart.destroy!
    entity.destroy!
    user.destroy!
    customer.destroy!
  end

  def submit(password, **options)
    post url, params: { email: user.email, password: password }.merge(options)
    expect(response).to have_http_status(:redirect)
  end

  it "keeps every failed attempt after real request rollback and rejects a later correct password" do
    limit = Authentication::User.maximum_attempts
    (limit + 1).times do |index|
      expect { submit("wrong-password") }.not_to change(EntityEntry, :count)
      expect(flash[:alert]).to be_present
      expect(user.reload.failed_attempts).to eq(index + 1)
    end
    expect(user).to be_access_locked
    expect { submit("password123") }.not_to change(EntityEntry, :count)
    expect(flash[:alert]).to be_present
    expect(user.reload).to be_access_locked
    expect(user.first_name).to eq("Test")
  end

  it "keeps a successful reset when a later business step rolls back" do
    user.update!(failed_attempts: 3)
    expect { submit("password123", fail_after: "yes") }.not_to change(EntityEntry, :count)
    expect(flash[:alert]).to be_present
    expect(user.reload.failed_attempts).to eq(0)
    expect(user.first_name).to eq("Test")
  end

  it "does not replay a failed attempt when the business transaction commits" do
    expect { submit("wrong-password", continue_after: "yes") }.to change(EntityEntry, :count).by(1)
    expect(flash[:notice]).to be_present
    expect(user.reload.failed_attempts).to eq(1)
    expect(user.first_name).to eq("Test")
  end

  it "does not log the submitted plaintext password in the flowchart context" do
    plaintext = "never-log-this-request-password"
    expect(AppLogger).not_to receive(:info).with(a_string_including(plaintext), any_args)
    submit(plaintext)
    expect(user.reload.failed_attempts).to eq(1)
  end

  it "sends one unlock email for a rolled-back threshold crossing and none for subsequent locked attempts" do
    allow(Authentication::User).to receive(:maximum_attempts).and_return(1)
    allow(Authentication::User).to receive(:unlock_strategy).and_return(:both)
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    # The app configures time-only unlocks and has no user_unlock_url. Exercise
    # real Devise token creation while observing only the mail delivery boundary.
    expect(Devise.mailer).to receive(:unlock_instructions).once.and_return(delivery)
    submit("wrong-password")
    expect(user.reload).to be_access_locked
    submit("wrong-password")
    expect(user.reload.failed_attempts).to eq(2)
  end

  it "sends one unlock email with the committed token when the flowchart handles authentication failure and commits" do
    allow(Authentication::User).to receive(:maximum_attempts).and_return(1)
    allow(Authentication::User).to receive(:unlock_strategy).and_return(:both)
    delivery = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    expect(Devise.mailer).to receive(:unlock_instructions).once do |account, raw_token, _options|
      expect(account.id).to eq(user.id)
      expect(user.reload.unlock_token).to eq(Devise.token_generator.digest(Authentication::User, :unlock_token, raw_token))
      delivery
    end

    submit("wrong-password", continue_after: "yes")
    expect(flash[:notice]).to be_present
    expect(user.reload.failed_attempts).to eq(1)
    expect(user).to be_access_locked
  end
end
