# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::SendActivities", type: :request do
  include_context "as admin"

  let(:other_customer) { create(:customer) }

  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  def send_activities_path = "/#{customer.id}/admin/modules/emails/send_activities"
  def send_activity_path(campaign) = "#{send_activities_path}/#{campaign.id}"

  # ---------------------------------------------------------------------------
  # GET index
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/send_activities" do
    let(:guard_path) { send_activities_path }

    it_behaves_like "an admin-guarded GET"
    it "renders the index with own campaigns" do
      campaign = create(:email_send_activity, customer: customer)
      get send_activities_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(campaign.name)
    end

    it "does not show another customer's campaigns" do
      other_campaign = create(:email_send_activity, customer: other_customer)
      get send_activities_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_campaign.name)
    end
  end

  # ---------------------------------------------------------------------------
  # GET new
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/send_activities/new" do
    let(:guard_path) { "#{send_activities_path}/new" }

    it_behaves_like "an admin-guarded GET"
    it "renders fields under the param key the controller requires (email_send_activity[...])" do
      # Regression guard: form_with would derive 'emails_campaign';
      # the controller requires :email_send_activity.
      get "#{send_activities_path}/new"
      expect(response.body).to include('name="email_send_activity[name]"')
      expect(response.body).not_to include('name="emails_campaign[name]"')
    end

    it "defaults to a client-side wizard with all step fields present" do
      get "#{send_activities_path}/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="email-send-activity-wizard"')
      expect(response.body).to include('data-email-send-activity-wizard-target="listsContainer"')
      expect(response.body).to include('data-action="click->email-send-activity-wizard#addList"')
      expect(response.body).to include('name="email_send_activity[email_template_id]"')
      expect(response.body).to include('name="email_send_activity[name]"')
      expect(response.body).to include('name="email_send_activity[send_timing]"')
      expect(response.body).to include('name="email_send_activity[recurrence_preset]"')
      expect(response.body).not_to include("Setup")
    end

    it "renders recurrence presets without an RRULE placeholder" do
      get "#{send_activities_path}/new"

      expect(response.body).to include('name="email_send_activity[recurrence_preset]"')
      expect(response.body).not_to include('placeholder="FREQ=DAILY;INTERVAL=1"')
    end
  end

  # ---------------------------------------------------------------------------
  # POST create
  # ---------------------------------------------------------------------------
  describe "POST /:cid/admin/modules/emails/send_activities" do
    let(:template) { create(:email_template, customer: customer, status: "active") }
    let(:list)     { create(:email_list, customer: customer) }
    let(:guard_path) { send_activities_path }

    it_behaves_like "an admin-guarded request", :post

    it "creates a campaign and redirects to show" do
      expect {
        post send_activities_path,
             params: { step: "review", email_send_activity: { name: "Spring Sale", email_template_id: template.id,
                                                         email_list_ids: [list.id], timezone: "UTC", send_timing: "now" } }
      }.to change(Emails::SendActivities::SendActivity, :count).by(1)

      created = Emails::SendActivities::SendActivity.unscoped.order(:created_at).last
      expect(response).to redirect_to(/emails\/send_activities\/#{created.id}/)
      expect(created.customer_id).to eq(customer.id)
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      expect {
        post send_activities_path,
             params: { step: "review", email_send_activity: { name: "Spring Sale", email_template_id: template.id,
                                                         email_list_ids: [list.id], timezone: "UTC", send_timing: "now" } }
      }.not_to change(Emails::SendActivities::SendActivity, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "creates a campaign with explicit name and redirects on success" do
      post send_activities_path,
           params: {
             step: "review",
             email_send_activity: {
               name: "My Campaign",
               email_template_id: template.id,
               email_list_ids: [list.id],
               timezone: "UTC", send_timing: "now"
             }
           }
      expect(response).to redirect_to(/emails\/send_activities\/\d+/)
      expect(Emails::SendActivities::SendActivity.where(customer: customer, name: "My Campaign")).to exist
    end

    it "maps the daily recurrence preset to its RRULE" do
      post send_activities_path,
           params: {
             step: "review",
             email_send_activity: {
               name: "Daily Campaign",
               email_template_id: template.id,
               email_list_ids: [list.id],
               recurrence_preset: "daily",
               timezone: "UTC", send_timing: "now"
             }
           }

      created = Emails::SendActivities::SendActivity.unscoped.order(:created_at).last
      expect(created.recurrence_rule).to eq("FREQ=DAILY;INTERVAL=1")
    end

    it "rejects an unsupported recurrence preset without raising" do
      expect {
        post send_activities_path,
             params: {
               step: "review",
               email_send_activity: {
                 name: "Unsupported Recurrence",
                 email_template_id: template.id,
                 email_list_ids: [list.id],
                 recurrence_preset: "every_minute",
                 timezone: "UTC", send_timing: "now"
               }
             }
      }.not_to raise_error

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("admin_modules.emails.send_activities.wizard.invalid_recurrence_preset"))
    end

    it "re-renders new with 422 on blank name" do
      post send_activities_path,
           params: { step: "review", email_send_activity: { name: "", email_template_id: template.id,
                                                       email_list_ids: [list.id], timezone: "UTC", send_timing: "now" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # C-SEC-1: cross-tenant FK on create — a tenant-A admin must not be able to
    # point a campaign at tenant B's list or template.
    describe "cross-tenant list/template rejection (C-SEC-1)" do
      let(:foreign_list)     { create(:email_list, customer: other_customer) }
      let(:foreign_template) { create(:email_template, customer: other_customer, status: "active") }

      it "rejects a foreign email_list_ids entry with 422 and does not create the campaign" do
        expect {
          post send_activities_path,
               params: { step: "review", email_send_activity: { name: "Hijack", email_template_id: template.id,
                                                           email_list_ids: [foreign_list.id], timezone: "UTC", send_timing: "now" } }
        }.not_to change(Emails::SendActivities::SendActivity, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "rejects a foreign email_template_id with 422 and does not create the campaign" do
        expect {
          post send_activities_path,
               params: { step: "review", email_send_activity: { name: "Hijack", email_template_id: foreign_template.id,
                                                           email_list_ids: [list.id], timezone: "UTC", send_timing: "now" } }
        }.not_to change(Emails::SendActivities::SendActivity, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "accepts same-tenant list and template ids (positive control)" do
        expect {
          post send_activities_path,
               params: { step: "review", email_send_activity: { name: "Legit", email_template_id: template.id,
                                                           email_list_ids: [list.id], timezone: "UTC", send_timing: "now" } }
        }.to change(Emails::SendActivities::SendActivity, :count).by(1)
        expect(response).to have_http_status(:found)
      end
    end

    describe "multi-list audience" do
      it "creates with multiple email_list_ids" do
        lists = create_list(:email_list, 2, customer: customer)
        expect {
          post send_activities_path, params: {
            email_send_activity: {
              name: "Multi",
              email_template_id: template.id,
              email_list_ids: lists.map(&:id),
              send_timing: "later",
              scheduled_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M"),
              timezone: "UTC",
              recurrence_preset: "none"
            }
          }
        }.to change(Emails::SendActivities::SendActivity, :count).by(1)

        activity = Emails::SendActivities::SendActivity.unscoped.order(:created_at).last
        expect(activity.email_lists).to match_array(lists)
      end

      it "rejects 11 lists without creating the campaign" do
        lists = create_list(:email_list, 11, customer: customer)
        expect {
          post send_activities_path, params: {
            email_send_activity: {
              name: "Too many",
              email_template_id: template.id,
              email_list_ids: lists.map(&:id),
              send_timing: "later",
              scheduled_at: 1.day.from_now.strftime("%Y-%m-%dT%H:%M"),
              timezone: "UTC",
              recurrence_preset: "none"
            }
          }
        }.not_to change(Emails::SendActivities::SendActivity, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Emails::SendActivities::SendActivity.where(name: "Too many")).to be_empty
      end
    end

    describe "single-save create" do
      it "creates pending on one POST with Send Now and may start processing" do
        expect {
          post send_activities_path, params: {
          email_send_activity: {
            name: "Wizard Campaign",
            email_list_ids: [list.id],
            email_template_id: template.id,
            timezone: "UTC",
            send_timing: "now",
            recurrence_preset: "none"
          }
        }
      }.to change(Emails::SendActivities::SendActivity, :count).by(1)

        campaign = Emails::SendActivities::SendActivity.unscoped.order(:created_at).last
        expect(response).to redirect_to("/#{customer.id}/admin/modules/emails/send_activities/#{campaign.id}")
        expect(campaign.name).to eq("Wizard Campaign")
        expect(campaign.email_lists).to eq([list])
        expect(campaign.email_template_id).to eq(template.id)
        expect(campaign.scheduled_at).to be_present
        expect(campaign.status).to be_in(%w[pending processing])
      end

      it "creates pending with a future schedule without starting" do
        post send_activities_path, params: {
          email_send_activity: {
            name: "Later Campaign",
            email_list_ids: [list.id],
            email_template_id: template.id,
            timezone: "UTC",
            send_timing: "later",
            scheduled_at: 2.days.from_now.strftime("%Y-%m-%dT%H:%M"),
            recurrence_preset: "none"
          }
        }
        campaign = Emails::SendActivities::SendActivity.unscoped.order(:created_at).last
        expect(campaign.status).to eq("pending")
        expect(campaign.scheduled_at).to be > Time.current
      end

      it "rejects create without schedule when timing is later" do
        expect {
          post send_activities_path, params: {
          email_send_activity: {
            name: "No Time",
            email_list_ids: [list.id],
            email_template_id: template.id,
            timezone: "UTC",
            send_timing: "later",
              recurrence_preset: "none"
            }
          }
        }.not_to change(Emails::SendActivities::SendActivity, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    # C-BUG-2: scheduled_at is submitted as a naive wall-clock string and must be
    # interpreted in the submitted timezone, not UTC.
    describe "timezone-aware scheduled_at round-trip (C-BUG-2)" do
      it "interprets the naive scheduled_at string in the submitted timezone" do
        post send_activities_path,
             params: {
               step: "review",
               email_send_activity: {
                 name: "TZ Campaign", email_template_id: template.id, email_list_ids: [list.id],
                 timezone: "America/New_York", scheduled_at: "2026-09-01T09:00", send_timing: "later"
               }
             }
        expect(response).to have_http_status(:found)
        created = Emails::SendActivities::SendActivity.unscoped.order(:created_at).last
        expected = Time.find_zone("America/New_York").parse("2026-09-01 09:00")
        expect(created.scheduled_at).to eq(expected)
        expect(created.scheduled_at.utc.hour).to eq(13) # 09:00 EDT == 13:00 UTC
      end

      it "does not 500 on a garbage scheduled_at value" do
        expect {
          post send_activities_path,
               params: {
                 step: "review",
                 email_send_activity: {
                   name: "Garbage TZ", email_template_id: template.id, email_list_ids: [list.id],
                   timezone: "America/New_York", scheduled_at: "not-a-date", send_timing: "later"
                 }
               }
        }.not_to raise_error
        expect(response.status).to be < 500
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET show
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/send_activities/:id" do
    let(:campaign) { create(:email_send_activity, customer: customer) }
    let(:guard_path) { send_activity_path(campaign) }

    it_behaves_like "an admin-guarded GET"
    it "links template and each list in a new tab" do
      lists = create_list(:email_list, 2, customer: customer)
      campaign = create(:email_send_activity, customer: customer, email_lists: lists)

      get send_activity_path(campaign)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('target="_blank"')
      expect(response.body).to include("link underline")
      expect(response.body).to include(admin_modules_emails_template_path(customer, campaign.email_template))
      lists.each do |list|
        expect(response.body).to include(admin_modules_emails_list_path(customer, list))
      end
    end

    it "uses the admin page title strip and retains campaign actions" do
      campaign = create(:email_send_activity, customer: customer, status: "pending")

      get send_activity_path(campaign)

      expect(response.body).to include(%(<h1 class="text-subtitle truncate">#{campaign.name}</h1>))
      expect(response.body).to include(I18n.t("common.actions.edit"))
      expect(response.body).to include(I18n.t("admin_modules.emails.send_activities.show.send_now"))
    end

    it "returns 404 for another customer's campaign" do
      other_campaign = create(:email_send_activity, customer: other_customer)
      get send_activity_path(other_campaign)
      expect(response).to have_http_status(:not_found)
    end

    it "exposes real delivery metrics rolled up from Emails::Message via email_send_activity_id (B7)" do
      campaign = create(:email_send_activity, :succeed, customer: customer)
      create(:email_message, customer: customer, email_send_activity_id: campaign.id,
            message_type: "campaign", status: "delivered")
      create(:email_message, customer: customer, email_send_activity_id: campaign.id,
            message_type: "campaign", status: "delivered")
      create(:email_message, customer: customer, email_send_activity_id: campaign.id,
            message_type: "campaign", status: "bounced")

      get send_activity_path(campaign)

      expect(response).to have_http_status(:ok)
      expect(campaign.delivery_counts).to eq("delivered" => 2, "bounced" => 1)

      page = Capybara::Node::Simple.new(response.body)
      cards = page.all(".card.border-l-4").map(&:text)
      expect(cards.find { |c| c.include?(I18n.t("admin_modules.emails.send_activities.show.delivered")) }).to match(/2/)
      expect(cards.find { |c| c.include?(I18n.t("admin_modules.emails.send_activities.show.bounced")) }).to match(/1/)
    end
  end

  # ---------------------------------------------------------------------------
  # GET edit
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/send_activities/:id/edit" do
    let(:campaign) { create(:email_send_activity, customer: customer) }
    let(:guard_path) { "#{send_activity_path(campaign)}/edit" }

    it_behaves_like "an admin-guarded GET"
    it "renders the edit form for draft and scheduled campaigns" do
      draft = create(:email_send_activity, customer: customer)
      get "#{send_activity_path(draft)}/edit"
      expect(response).to have_http_status(:ok)

      scheduled = create(:email_send_activity, :pending, customer: customer)
      get "#{send_activity_path(scheduled)}/edit"
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for another customer's campaign" do
      other_campaign = create(:email_send_activity, customer: other_customer)
      get "#{send_activity_path(other_campaign)}/edit"
      expect(response).to have_http_status(:not_found)
    end

    # B11: editing a live/sent campaign is guarded.
    %w[processing succeed cancelled failed].each do |blocked_status|
      it "redirects with a flash alert instead of rendering edit for a '#{blocked_status}' campaign" do
        campaign = create(:email_send_activity, customer: customer, status: blocked_status)
        get "#{send_activity_path(campaign)}/edit"
        expect(response).to redirect_to(send_activity_path(campaign))
        follow_redirect!
        expect(response.body).to include(I18n.t("admin_modules.flash.send_activities.edit_status_blocked",
                                               status: I18n.t("admin_modules.emails.send_activities.statuses.#{blocked_status}")))
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update
  # ---------------------------------------------------------------------------
  describe "PATCH /:cid/admin/modules/emails/send_activities/:id" do
    let(:campaign) { create(:email_send_activity, customer: customer) }
    let(:guard_path) { send_activity_path(campaign) }

    it_behaves_like "an admin-guarded request", :patch
    it "updates the campaign and redirects to show" do
      campaign = create(:email_send_activity, customer: customer)
      patch send_activity_path(campaign),
            params: {
              step: "review",
              email_send_activity: {
                name: "Renamed Campaign",
                email_template_id: campaign.email_template_id,
                email_list_ids: campaign.email_list_ids,
                timezone: "UTC", send_timing: "now"
              }
            }
      expect(response).to redirect_to(/emails\/send_activities\/#{campaign.id}/)
      expect(campaign.reload.name).to eq("Renamed Campaign")
    end

    it "re-renders edit with 422 on blank name" do
      campaign = create(:email_send_activity, customer: customer)
      patch send_activity_path(campaign),
            params: {
              step: "review",
              email_send_activity: {
                name: "",
                email_template_id: campaign.email_template_id,
                email_list_ids: campaign.email_list_ids,
                timezone: "UTC", send_timing: "now"
              }
            }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # C-SEC-1: re-pointing an existing (own) campaign at a foreign list/template.
    describe "cross-tenant list/template rejection on update (C-SEC-1)" do
      let(:campaign)          { create(:email_send_activity, customer: customer) }
      let(:foreign_list)      { create(:email_list, customer: other_customer) }
      let(:foreign_template)  { create(:email_template, customer: other_customer, status: "active") }

      it "rejects re-pointing email_list_ids at a foreign list with 422" do
        original_list_ids = campaign.email_list_ids
        patch send_activity_path(campaign),
              params: {
                step: "review",
                email_send_activity: {
                  name: campaign.name,
                  email_template_id: campaign.email_template_id,
                  email_list_ids: [foreign_list.id],
                  timezone: "UTC", send_timing: "now"
                }
              }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(campaign.reload.email_list_ids).to eq(original_list_ids)
      end

      it "rejects re-pointing email_template_id at a foreign template with 422" do
        original_template_id = campaign.email_template_id
        patch send_activity_path(campaign),
              params: {
                step: "review",
                email_send_activity: {
                  name: campaign.name,
                  email_template_id: foreign_template.id,
                  email_list_ids: campaign.email_list_ids,
                  timezone: "UTC", send_timing: "now"
                }
              }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(campaign.reload.email_template_id).to eq(original_template_id)
      end
    end

    it "returns 404 when updating another customer's campaign" do
      other_campaign = create(:email_send_activity, customer: other_customer)
      patch send_activity_path(other_campaign),
            params: {
              step: "review",
              email_send_activity: {
                name: "Hijack",
                email_template_id: other_campaign.email_template_id,
                email_list_ids: other_campaign.email_list_ids,
                timezone: "UTC", send_timing: "now"
              }
            }
      expect(response).to have_http_status(:not_found)
    end

    # B11: updating a live/sent campaign is guarded — the update never runs.
    %w[processing succeed cancelled failed].each do |blocked_status|
      it "refuses to update a '#{blocked_status}' campaign and redirects with an alert" do
        campaign = create(:email_send_activity, customer: customer, status: blocked_status)
        original_name = campaign.name

        patch send_activity_path(campaign),
              params: {
                step: "review",
                email_send_activity: {
                  name: "Should Not Apply",
                  email_template_id: campaign.email_template_id,
                  email_list_ids: campaign.email_list_ids,
                  timezone: "UTC", send_timing: "now"
                }
              }

        expect(response).to redirect_to(send_activity_path(campaign))
        expect(campaign.reload.name).to eq(original_name)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy
  # ---------------------------------------------------------------------------
  describe "DELETE /:cid/admin/modules/emails/send_activities/:id" do
    let(:campaign) { create(:email_send_activity, customer: customer) }
    let(:guard_path) { send_activity_path(campaign) }

    it_behaves_like "an admin-guarded request", :delete
    it "destroys the campaign and redirects to index" do
      campaign = create(:email_send_activity, customer: customer)
      expect {
        delete send_activity_path(campaign)
      }.to change(Emails::SendActivities::SendActivity, :count).by(-1)
      expect(response).to redirect_to(/emails\/send_activities/)
      expect(Emails::SendActivities::SendActivity.find_by(id: campaign.id)).to be_nil
    end

    it "honors the model's aborted destroy when sending starts after the controller's status check" do
      campaign = create(:email_send_activity, customer: customer, status: "pending")
      allow_any_instance_of(Emails::SendActivities::SendActivity).to receive(:destroy).and_wrap_original do |original, *args|
        original.receiver.update_columns(status: "processing")
        original.call(*args)
      end

      expect { delete send_activity_path(campaign) }.not_to change(Emails::SendActivities::SendActivity, :count)

      expect(response).to redirect_to(send_activity_path(campaign))
      expect(campaign.reload.status).to eq("processing")
      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to be_present
    end

    it "returns 404 when deleting another customer's campaign" do
      other_campaign = create(:email_send_activity, customer: other_customer)
      expect {
        delete send_activity_path(other_campaign)
      }.not_to change(Emails::SendActivities::SendActivity, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "refuses to delete a sending campaign" do
      campaign = create(:email_send_activity, :processing, customer: customer,
                        email_template: create(:email_template, customer: customer),
                        email_lists: [create(:email_list, customer: customer)])
      delete send_activity_path(campaign)
      expect(Emails::SendActivities::SendActivity.exists?(campaign.id)).to be true
    end

    it "allows deleting a draft campaign" do
      campaign = create(:email_send_activity, customer: customer,
                        email_template: create(:email_template, customer: customer),
                        email_lists: [create(:email_list, customer: customer)])
      delete send_activity_path(campaign)
      expect(Emails::SendActivities::SendActivity.exists?(campaign.id)).to be false
    end

    # B11: a `sent` campaign is kept for its metrics — deleting it would orphan
    # the per-recipient Emails::Message ledger. DESTROYABLE_STATUSES = draft, cancelled.
    %w[succeed processing failed].each do |blocked_status|
      it "refuses to delete a '#{blocked_status}' campaign and redirects with an alert" do
        campaign = create(:email_send_activity, customer: customer, status: blocked_status)
        delete send_activity_path(campaign)
        expect(response).to redirect_to(send_activity_path(campaign))
        expect(Emails::SendActivities::SendActivity.exists?(campaign.id)).to be true
      end
    end

    it "allows deleting a cancelled campaign" do
      campaign = create(:email_send_activity, customer: customer, status: "cancelled")
      delete send_activity_path(campaign)
      expect(response).to redirect_to(/emails\/send_activities/)
      expect(Emails::SendActivities::SendActivity.exists?(campaign.id)).to be false
    end
  end
end
