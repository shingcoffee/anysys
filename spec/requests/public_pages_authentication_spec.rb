# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page generated session authentication", type: :request do
  let(:customer) { create(:customer) }
  let(:user) { create(:user, :member, customer: customer) }
  let(:entity) do
    schema = %w[principal_id current_user_id current_user_role audience].map { |key| { "name_slug" => key } }
    create(:entity, customer: customer, property_schema: schema.to_json)
  end
  let(:page) do
    method = CodeGenerators::ElementTypes::Process::Security::AuthenticateGenerator.new(
      { "config" => { "authMethod" => "session", "resultVar" => "authenticated_user" } }, {}
    ).generate_step_method
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public, customer: customer, entity: entity, launched: true,
             configuration: { metadata: { entity_id: entity.id }, fields: [] }.to_json)
    end.tap do |page|
      bind_page_flowchart(page, code: <<~RUBY)
        class SessionSubmissionActivity#{SecureRandom.hex(4)} < Trailblazer::Activity::Railway
          step :authenticate
          step :record_principal
          #{method}
          def record_principal(ctx, **)
            ctx[:model].data_json = ctx[:model].data_json.merge(
              "principal_id" => ctx[:authenticated_user].id, "current_user_id" => ctx[:current_user_id],
              "current_user_role" => ctx[:current_user_role], "audience" => ctx[:audience]
            )
            ctx[:model].save!
            true
          end
        end
      RUBY
    end
  end
  let(:url) { "/#{customer.id}/page/#{page.public_uuid}" }

  def establish_session(principal = user)
    sign_in principal
    get url
    expect(session["warden.user.user.key"]).to eq(Authentication::User.serialize_into_session(principal))
    expect(session[:user_id]).to be_nil
  end

  it "round-trips a Devise session into a generated authentication step through page submit" do
    establish_session
    expect { post url }.to change(EntityEntry, :count).by(1)
    expect(EntityEntry.last.data_json).to include(
      "principal_id" => user.id, "current_user_id" => user.id,
      "current_user_role" => "member", "audience" => "member"
    )
    expect(flash[:notice]).to eq(I18n.t("public_views.flash.response_submitted"))
  end

  it "rejects the old cookie after a password change invalidates authenticatable_salt" do
    establish_session
    user.update!(password: "changed-password123")
    expect { post url }.not_to change(EntityEntry, :count)
    expect(flash[:alert]).to be_present
    expect(session["warden.user.user.key"]).to be_nil
  end

  it "rejects a valid session belonging to another tenant" do
    establish_session(create(:user, :member))
    expect { post url }.not_to change(EntityEntry, :count)
    expect(flash[:alert]).to be_present
  end

  it "does not authenticate IDs or session-shaped data submitted by an anonymous visitor" do
    expect {
      post url, params: { current_user_id: user.id, session: { user_id: user.id }, authentication: { user_id: user.id } }
    }.not_to change(EntityEntry, :count)
    expect(flash[:alert]).to be_present
  end
end
