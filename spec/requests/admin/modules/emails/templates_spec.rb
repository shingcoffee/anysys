# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::Templates", type: :request do
  include_context "as admin"

  let!(:email_module) { enable_module!("email", customer, name: "Email") }

  let(:other_customer) { create(:customer) }
  let(:base_path)      { "/#{customer.id}/admin/modules/emails/templates" }

  # The "email" module is auto-enabled via Customer#after_create — no manual enablement needed.

  # ---------------------------------------------------------------------------
  # GET index
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/templates" do
    let(:guard_path) { base_path }

    it_behaves_like "an admin-guarded GET"
    it "uses Content and Templates for the page breadcrumb and title" do
      get admin_modules_emails_templates_path(customer)

      expect(response.body).to include(I18n.t("feature_modules.email.entries.content"))
      expect(response.body).to include(I18n.t("feature_modules.email.tabs.templates"))
      heading = Nokogiri::HTML(response.body).at("h1")&.text.to_s
      expect(heading).to include(I18n.t("feature_modules.email.tabs.templates"))
      expect(heading).not_to include(I18n.t("feature_modules.email.entries.send_activities"))
      expect(response.body).not_to include("/admin/modules/emails/messages")
    end

    it "renders the templates index with own templates" do
      template = create(:email_template, customer: customer)
      get base_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(template.name)
    end

    it "stacks the subject under the template name" do
      create(:email_template, customer: customer, name: "Welcome", subject: "Hello there", editor_type: "rich_text", body: "<p>Hi</p>")
      get base_path
      expect(response.body).to include("Welcome")
      expect(response.body).to include("Hello there")
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.index.columns.template"))
    end

    it "renders token labels, not storage UUIDs, in the subject subtitle" do
      template = create(:email_template, customer: customer) # factory subject embeds a {{uuid}} token
      uuid = template.subject[/[0-9a-f-]{36}/]
      expect(uuid).to be_present
      token = Emails::TemplateToken.platform.find_by!(uuid: uuid)
      label = Emails::TokenCatalog.for_customer(customer.id).editor_label(token)

      get base_path

      expect(response.body).not_to include(uuid)
      expect(response.body).to include("{{#{label}}}")
    end

    it "keeps per_page in pagination and toolbar links" do
      create_list(:email_template, 2, customer: customer)

      get base_path, params: { per_page: 1 }

      expect(response.body).to include("per_page=1")
    end

    it "links the template name to its detail page, not straight into the editor" do
      template = create(:email_template, customer: customer, status: "draft")
      get base_path

      name_link = Nokogiri::HTML(response.body).css("tbody td a.link").first
      expect(name_link).not_to be_nil
      expect(name_link[:href]).to eq(admin_modules_emails_template_path(customer, template))
      expect(name_link[:href]).not_to include("/edit")
    end

    it "exposes Edit and Preview as compact row actions without a kebab" do
      template = create(:email_template, customer: customer, status: "draft")
      get base_path

      expect(response.body).to include(I18n.t("common.actions.edit"))
      expect(response.body).to include(edit_admin_modules_emails_template_path(customer, template))
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.actions.preview"))
      expect(response.body).to include(preview_admin_modules_emails_template_path(customer, template))

      table = Nokogiri::HTML(response.body).at_css("turbo-frame#admin-table")
      expect(table.css("[data-controller~='menu-placement']")).to be_empty
      expect(table.css("summary").map { |node| node["aria-label"] }).not_to include(I18n.t("common.actions.more"))
      row_actions_html = Nokogiri::HTML(response.body).css(
        "turbo-frame#admin-table tbody td:last-child, turbo-frame#admin-table .sm\\:hidden .shrink-0"
      ).map(&:to_html).join
      expect(row_actions_html).not_to include("<details")
      expect(row_actions_html).not_to include(duplicate_admin_modules_emails_template_path(customer, template))
      expect(row_actions_html).not_to include(I18n.t("common.actions.delete"))
      expect(row_actions_html).not_to include(I18n.t("admin_modules.emails.templates.index.delete_confirm"))
      expect(row_actions_html).not_to include('data-turbo-method="delete"')
      expect(row_actions_html).not_to include(I18n.t("admin_modules.emails.templates.status.actions.set_active"))
      expect(row_actions_html).not_to include(I18n.t("admin_modules.emails.templates.status.actions.set_retired"))
      expect(response.body).not_to include(I18n.t("maint_core.nav.versions"))
      expect(response.body).not_to include('data-controller="versions"')
    end

    it "reports how many templates are listed" do
      create_list(:email_template, 2, customer: customer)
      get base_path
      expect(response.body).to include(I18n.t("chrome.admin_table.result_count", count: 2))
    end

    it "renders the updated time as relative text with the exact stamp on hover" do
      create(:email_template, customer: customer, updated_at: 2.days.ago)
      get base_path
      expect(response.body).to include(I18n.t("chrome.admin_table.time_ago", time: "2 days"))
      expect(response.body).to include("<time")
    end

    it "shows how many emails reference each template" do
      template = create(:email_template, customer: customer)
      create_list(:email_message, 2, customer: customer, email_template_id: template.id)

      get base_path

      expect(response.body).to include(I18n.t("admin_modules.emails.templates.index.columns.messages"))
      cells = Nokogiri::HTML(response.body).css("tbody td").map { |td| td.text.strip }
      expect(cells).to include("2") # the two messages referencing the template
    end

    it "tones status badges by lifecycle state" do
      create(:email_template, customer: customer, status: "draft")
      create(:email_template, customer: customer, status: "active")

      get base_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css(".badge-warning").any? { |b| b.text.strip == I18n.t("common.status.draft") }).to be(true)
      expect(doc.css(".badge-success").any? { |b| b.text.strip == I18n.t("common.status.active") }).to be(true)
    end

    it "renders a removable chip and clear-all for each active filter" do
      create(:email_template, customer: customer, status: "active")
      get base_path, params: { status: "active" }

      expect(response.body).to include(I18n.t("chrome.admin_table.clear_filters"))
      expect(response.body).to include(
        I18n.t("chrome.admin_table.remove_filter",
               label: I18n.t("admin_modules.emails.templates.index.filters.status"))
      )
    end

    it "filters by status" do
      create(:email_template, customer: customer, name: "Draft Rich", status: "draft",
             editor_type: "rich_text", body: "Hello")
      create(:email_template, customer: customer, name: "Active Code", status: "active",
             editor_type: "code", body_html: "<p>Hi</p>")

      get base_path, params: { status: "active" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Active Code")
      expect(response.body).not_to include("Draft Rich")
      expect(response.body).to include(%(name="status"))
      expect(response.body).not_to include(%(name="editor_type"))
    end

    it "shows filter empty state when filters match nothing" do
      create(:email_template, customer: customer, name: "Draft Only", status: "draft")

      get base_path, params: { status: "retired" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("chrome.admin_table.no_filter_matches"))
      expect(response.body).not_to include("Draft Only")
    end

    it "does not leak another customer's templates when filtering by status" do
      create(:email_template, customer: customer, name: "Own Draft", status: "draft")
      foreign = create(:email_template, customer: other_customer, name: "Foreign Active Match", status: "active")

      get base_path, params: { status: "active" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(foreign.name)
    end

    it "returns JSON options for the send-activity wizard refresh" do
      active = create(:email_template, customer: customer, name: "Active Own", status: "active")
      create(:email_template, customer: customer, name: "Draft Own", status: "draft")
      create(:email_template, customer: other_customer, name: "Foreign Active", status: "active")

      get base_path, as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body
      expect(payload).to contain_exactly({ "id" => active.id, "name" => "Active Own" })
    end

    it "does not expose another customer's templates" do
      other_tmpl = create(:email_template, customer: other_customer,
                           name: "Foreign Tenant Template XYZ")
      get base_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_tmpl.name)
    end
  end

  # ---------------------------------------------------------------------------
  # GET new
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/templates/new" do
    let(:guard_path) { "#{base_path}/new" }

    it_behaves_like "an admin-guarded GET"
    it "renders fields under the param key the controller requires (email_template[...])" do
      # Regression guard: form_with derives 'emails_template' from the namespaced
      # model, but the controller does params.require(:email_template). The form
      # must use scope: :email_template, or creates silently no-op.
      get "#{base_path}/new"
      expect(response.body).to include('name="email_template[name]"')
      expect(response.body).not_to include('name="emails_template[name]"')
    end

    it "marks name, subject, and body as required" do
      get "#{base_path}/new"
      expect(response.body).to include("form-label-required")
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.form.rich_text_body"))
      expect(response.body).to match(/<input[^>]*name="email_template\[name\]"[^>]*\brequired\b|<input[^>]*\brequired\b[^>]*name="email_template\[name\]"/)
      expect(response.body).to match(/<input[^>]*name="email_template\[subject\]"[^>]*\brequired\b|<input[^>]*\brequired\b[^>]*name="email_template\[subject\]"/)
    end

    it "renders a lexxy-editor element (rich_text is the default editor_type)" do
      get "#{base_path}/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("lexxy-editor")
      expect(response.body).not_to include("rhino-editor")
    end

    it "renders the Insert token searchable select with human labels (not UUID option values)" do
      get "#{base_path}/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="searchable-select"')
      expect(response.body).to include('id="email_template_token_insert"')
      expect(response.body).to include(Emails::TemplateToken.platform.find_by!(uuid: platform_token_uuid("email")).display_label)
      # Insert picker option values must be labels — storage UUIDs never reach
      # the picker DOM; label→uuid mapping happens server-side on save.
      expect(response.body).not_to match(
        /data-searchable-select-options-value="[^"]*#{Regexp.escape(platform_token_uuid("email"))}/
      )
    end

    it "renders the split compose/preview workspace with live preview" do
      get "#{base_path}/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="remote-template-preview"')
      expect(response.body).to include('id="template-preview"')
      expect(response.body).to include('id="dry_run_to"')
      # Compose and preview are side-by-side cards, not tabs
      expect(response.body).not_to include("workspace-tabs")
      expect(response.body).not_to include("template-workspace-layout")
      expect(response.body).not_to include("Variables Board")
      # Editor mode is a segmented control backed by the visually hidden select
      expect(response.body).to include('data-template-editor-mode-target="modeButton"')
      expect(response.body).to include("template-editor-mode#choose")
      # Lexxy fires lexxy:change (not trix-change) — wire auto-refresh to that event
      expect(response.body).to include("lexxy:change->remote-template-preview#debouncedLoadPreview")
      expect(response.body).not_to include("trix-change->remote-template-preview")
      # New-tab preview must not rely on form submit (edit forms carry _method=patch)
      expect(response.body).to include("remote-template-preview#openFullPagePreview")
    end

    it "renders only the spacious creation fields and omits advanced edit-only settings" do
      get "#{base_path}/new"
      expect(response).to have_http_status(:ok)
      
      # Should render basic fields
      expect(response.body).to include('name="email_template[name]"')
      expect(response.body).to include('name="email_template[subject]"')
      
      # New templates activate by default; unchecking still sends the draft value.
      checkbox = Nokogiri::HTML(response.body).at_css('input[type="checkbox"][name="email_template[status]"]')
      expect(checkbox).to be_present
      expect(checkbox["checked"]).to eq("checked")
      expect(checkbox["value"]).to eq("active")
      expect(Nokogiri::HTML(response.body).at_css('input[type="hidden"][name="email_template[status]"]')["value"]).to eq("draft")
      
      # Should NOT render advanced settings that only exist in edit view
      expect(response.body).not_to include('name="email_template[category]"')
      expect(response.body).not_to include('name="email_template[email_stream_id]"')
      expect(response.body).not_to include('name="email_template[variables]"')
      expect(response.body).not_to include('name="email_template[key]"')
    end
  end

  # ---------------------------------------------------------------------------
  # POST create
  # ---------------------------------------------------------------------------
  describe "POST /:cid/admin/modules/emails/templates" do
    let(:guard_path) { base_path }

    it_behaves_like "an admin-guarded request", :post

    let(:valid_params) do
      {
        email_template: {
          name: "Welcome V2",
          subject: "Welcome!",
          body_html: "<p>Hi #{platform_token('first_name')}</p>",
          editor_type: "code",
          status: "active"
        }
      }
    end

    it "creates a template and redirects to index" do
      expect {
        post base_path, params: valid_params
      }.to change(Emails::Template, :count).by(1)

      expect(response).to redirect_to(/emails\/templates/)
      created = Emails::Template.unscoped.order(:created_at).last
      expect(created.customer_id).to eq(customer.id)
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      expect {
        post base_path, params: valid_params
      }.not_to change(Emails::Template, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "verifies the created template record exists by name" do
      post base_path, params: valid_params
      expect(response).to redirect_to(/emails\/templates/)
      expect(Emails::Template.where(customer: customer, name: "Welcome V2")).to exist
    end

    it "creates a draft template when status is set to draft" do
      params = valid_params.deep_merge(email_template: { name: "Draft Tmpl", status: "draft" })
      post base_path, params: params
      expect(response).to redirect_to(/emails\/templates/)
      tmpl = Emails::Template.find_by!(customer: customer, name: "Draft Tmpl")
      expect(tmpl.status).to eq("draft")
    end

    it "creates an active template when status is set to active" do
      params = valid_params.deep_merge(email_template: { name: "Active Tmpl", status: "active" })
      post base_path, params: params
      expect(response).to redirect_to(/emails\/templates/)
      tmpl = Emails::Template.find_by!(customer: customer, name: "Active Tmpl")
      expect(tmpl.status).to eq("active")
    end

    it "re-renders new with 422 on blank name and subject" do
      post base_path,
           params: {
             email_template: {
               name: "",
               subject: "",
               body_html: "",
               editor_type: "code",
               status: "active"
             }
           }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # -------------------------------------------------------------------------
    # Rich-text (Trix) editor mode
    # -------------------------------------------------------------------------
    it "creates a rich_text template: stores the body and populates body_html" do
      post base_path,
           params: {
             email_template: {
               name: "Rich Welcome",
               subject: "Hi there",
               body: "<div>Hi #{platform_token('first_name')}</div>",
               editor_type: "rich_text",
               status: "active"
             }
           }

      expect(response).to redirect_to(/emails\/templates/)

      tmpl = Emails::Template.find_by!(customer: customer, name: "Rich Welcome")
      expect(tmpl.editor_type).to eq("rich_text")

      # The rich_text body was stored in Action Text
      expect(tmpl.body.to_s).to include("Hi")
      expect(tmpl.body.to_s).to include(platform_token('first_name'))

      # The before_validation callback compiled body → body_html
      expect(tmpl.body_html).to be_present
      expect(tmpl.body_html).to include("Hi #{platform_token('first_name')}")
    end
  end

  # ---------------------------------------------------------------------------
  # GET / POST preview
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/templates/:id/preview" do
    let(:template) { create(:email_template, customer: customer) }
    let(:guard_path) { "#{base_path}/#{template.id}/preview" }

    it_behaves_like "an admin-guarded GET"
    it "renders a dedicated author preview with {{Label}} tokens and no sample fill" do
      token = platform_token("first_name")
      label = Emails::TemplateToken.platform.find_by!(uuid: platform_token_uuid("first_name")).display_label
      tmpl = create(:email_template, customer: customer, editor_type: "code",
                    name: "Welcome",
                    subject: "Hi #{token}",
                    body_html: "<p>Dear #{token}</p>",
                    body_text: "Dear #{token}")

      get "#{base_path}/#{tmpl.id}/preview"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.preview_page.title"))
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.preview_page.hint"))
      expect(response.body).to include("{{#{label}}}")
      expect(response.body).not_to include(token)

      frame = Nokogiri::HTML(response.body).css("iframe[sandbox]").first
      expect(frame).not_to be_nil
      expect(frame[:srcdoc]).to include("Dear {{#{label}}}")
      expect(frame[:srcdoc]).to include("<!DOCTYPE html>")
      expect(frame[:srcdoc]).not_to include(token)
    end
  end

  describe "POST /:cid/admin/modules/emails/templates/preview" do
    # Collection-preview auth + HTML/JSON render live in template_dry_runs_spec.rb.
    it "swaps cid:blob image sources for browser-loadable blob URLs" do
      blob = Current.set(customer: customer) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("fake image data"), filename: "hero.png", content_type: "image/png"
        )
      end
      attachment_html = ActionText::Attachment.from_attachable(blob).to_s

      post "#{base_path}/preview", params: {
        email_template: {
          subject: "With image",
          body: "<div>#{attachment_html}</div>",
          editor_type: "rich_text"
        }
      }, as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["body_html"]).to include(Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true))
      expect(json["body_html"]).not_to include("cid:blob-")
      expect(json["body_srcdoc"]).to include("<!DOCTYPE html>")
    end

    it "keeps a foreign image as CID without generating its signed browser URL" do
      foreign = Current.set(customer: other_customer) do
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new("foreign image"), filename: "foreign.png", content_type: "image/png")
      end
      attachment_html = ActionText::Attachment.from_attachable(foreign).to_s

      post "#{base_path}/preview", params: {
        email_template: { subject: "Foreign image", body: "<div>#{attachment_html}</div>", editor_type: "rich_text" }
      }, as: :json

      expect(response).to have_http_status(:ok)
      html = response.parsed_body["body_html"]
      expect(html).to include("cid:blob-#{foreign.id}")
      expect(html).not_to include(Rails.application.routes.url_helpers.rails_blob_url(foreign, only_path: true))
    end
  end

  # Collection POST test_send auth + dry-run JSON live in template_dry_runs_spec.rb.

  # ---------------------------------------------------------------------------
  # GET edit
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/templates/:id/edit" do
    let(:template) { create(:email_template, customer: customer) }
    let(:guard_path) { "#{base_path}/#{template.id}/edit" }

    it_behaves_like "an admin-guarded GET"
    it "renders the split workspace without Settings or Version History tabs" do
      tmpl = create(:email_template, customer: customer)
      get "#{base_path}/#{tmpl.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-tabs-id="settings"')
      expect(response.body).not_to include('data-tabs-id="versions"')
      expect(response.body).not_to include("workspace-tabs")
      expect(response.body).to include('id="template-preview"')
      expect(response.body).to include('data-controller="searchable-select"')
      expect(response.body).not_to include("template-workspace-layout")
      expect(response.body).not_to include("Variables Board")
    end

    it "isolates the live HTML preview in a sandboxed iframe" do
      get "#{base_path}/#{template.id}/edit"

      frame = Nokogiri::HTML(response.body).css("iframe[data-remote-template-preview-target='iframe']").first
      expect(frame).not_to be_nil
      expect(frame[:sandbox]).to eq("")
    end

    it "never exposes storage UUIDs in the rich-text editor value" do
      first = platform_token_uuid("first_name")
      label = Emails::TemplateToken.platform.find_by!(uuid: platform_token_uuid("first_name")).display_label
      html = "<p>Hello #{platform_token('first_name')}</p>"
      tmpl = create(
        :email_template,
        customer: customer,
        editor_type: "code",
        subject: "Hi #{platform_token('first_name')}",
        body_html: html
      )
      # Switch to rich_text and seed ActionText with the stored UUID tokens.
      tmpl.update_columns(editor_type: "rich_text")
      tmpl.body = html
      tmpl.body.save!

      get "#{base_path}/#{tmpl.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("{{#{label}}}")
      # Lexxy value / subject inputs must show labels, never the raw UUID token.
      expect(response.body).not_to match(/name="email_template\[subject\]"[^>]*value="[^"]*#{Regexp.escape(first)}/i)
      expect(response.body).not_to include("{{#{first}}}")
    end

    it "returns 404 for another customer's template" do
      other_tmpl = create(:email_template, customer: other_customer)
      get "#{base_path}/#{other_tmpl.id}/edit"
      expect(response).to have_http_status(:not_found)
    end

    it "previews a historical version's subject unsaved when ?version= is given" do
      tmpl = create(:email_template, customer: customer, subject: "Original subject")
      v1 = tmpl.template_versions.order(:version_number).first
      tmpl.update!(subject: "Changed subject")

      get "#{base_path}/#{tmpl.id}/edit", params: { version: v1.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Original subject")
      expect(tmpl.reload.subject).to eq("Changed subject") # unsaved: DB unchanged
    end

    it "ignores an unknown version id and shows the current template" do
      tmpl = create(:email_template, customer: customer, subject: "Current subject")

      get "#{base_path}/#{tmpl.id}/edit", params: { version: 0 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Current subject")
    end

    it "does not apply a version belonging to another customer's template" do
      tmpl = create(:email_template, customer: customer, subject: "Current subject")
      other_tmpl = create(:email_template, customer: other_customer, subject: "Foreign subject")
      other_version = other_tmpl.template_versions.order(:version_number).first

      get "#{base_path}/#{tmpl.id}/edit", params: { version: other_version.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Current subject")
      expect(response.body).not_to include("Foreign subject")
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH update
  # ---------------------------------------------------------------------------
  describe "PATCH /:cid/admin/modules/emails/templates/:id" do
    let(:template) { create(:email_template, customer: customer) }
    let(:guard_path) { "#{base_path}/#{template.id}" }

    it_behaves_like "an admin-guarded request", :patch
    it "updates the template and redirects" do
      tmpl = create(:email_template, customer: customer)
      patch "#{base_path}/#{tmpl.id}",
            params: {
              email_template: {
                name: "Updated Name",
                subject: tmpl.subject,
                body_html: tmpl.body_html,
                editor_type: tmpl.editor_type
              }
            }
      expect(response).to redirect_to(/emails\/templates/)
      expect(tmpl.reload.name).to eq("Updated Name")
    end

    it "does not update status through the edit endpoint" do
      tmpl = create(:email_template, customer: customer, status: "active")

      patch "#{base_path}/#{tmpl.id}",
            params: {
              email_template: {
                name: tmpl.name,
                subject: tmpl.subject,
                body_html: tmpl.body_html,
                editor_type: tmpl.editor_type,
                status: "draft"
              }
            }

      expect(response).to redirect_to(/emails\/templates/)
      expect(tmpl.reload.status).to eq("active")
    end

    it "re-renders edit with 422 on blank name and subject" do
      tmpl = create(:email_template, customer: customer)
      patch "#{base_path}/#{tmpl.id}",
            params: {
              email_template: {
                name: "",
                subject: "",
                body_html: "",
                editor_type: tmpl.editor_type
              }
            }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 when updating another customer's template" do
      other_tmpl = create(:email_template, customer: other_customer)
      patch "#{base_path}/#{other_tmpl.id}",
            params: {
              email_template: {
                name: "Hijack",
                subject: "x",
                body_html: "x",
                editor_type: "code",
                status: "active"
              }
            }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH status
  # ---------------------------------------------------------------------------
  describe "PATCH /:cid/admin/modules/emails/templates/:id/status" do
    let(:template) { create(:email_template, customer: customer) }
    let(:guard_path) { status_admin_modules_emails_template_path(customer.id, template) }

    it_behaves_like "an admin-guarded request", :patch
    it "updates status when no non-terminal campaign references the template" do
      template = create(:email_template, customer: customer, status: "draft")

      patch status_admin_modules_emails_template_path(customer.id, template), params: { status: "active" }

      expect(response).to redirect_to(admin_modules_emails_templates_path(customer.id))
      expect(template.reload.status).to eq("active")
    end

    it "rejects draft when a non-terminal campaign references the template" do
      template = create(:email_template, customer: customer, status: "active")
      create(:email_send_activity, customer: customer, email_template: template, status: "pending")

      patch status_admin_modules_emails_template_path(customer.id, template), params: { status: "draft" }

      expect(template.reload.status).to eq("active")
      expect(flash[:alert]).to eq(I18n.t("admin_modules.emails.templates.status.in_use"))
    end

    it "rejects cross-tenant status changes" do
      other = create(:email_template, customer: other_customer, status: "draft")

      patch status_admin_modules_emails_template_path(customer.id, other), params: { status: "active" }

      expect(response).to have_http_status(:not_found)
      expect(other.reload.status).to eq("draft")
    end
  end

  # ---------------------------------------------------------------------------
  # GET show
  # ---------------------------------------------------------------------------
  describe "GET /:cid/admin/modules/emails/templates/:id" do
    let(:template) { create(:email_template, customer: customer) }
    let(:guard_path) { "#{base_path}/#{template.id}" }

    it_behaves_like "an admin-guarded GET"
    it "renders the template detail page with its metadata" do
      tmpl = create(:email_template, customer: customer, name: "Welcome",
                    subject: "Hello there", status: "active", editor_type: "code",
                    body_html: "<p>Body copy</p>", body_text: "Body copy")

      get "#{base_path}/#{tmpl.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Welcome", "Hello there")
      expect(response.body).to include(I18n.t("common.status.active"))
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.form.editor_types.code"))
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.show.body_label"))
    end

    it "isolates the authored email HTML in a sandboxed frame" do
      tmpl = create(:email_template, customer: customer, editor_type: "code",
                    body_html: "<p>Body copy</p>")

      get "#{base_path}/#{tmpl.id}"

      frame = Nokogiri::HTML(response.body).css("iframe[sandbox]").first
      expect(frame).not_to be_nil
      expect(frame[:sandbox]).to eq("")
      expect(frame[:srcdoc]).to include("Body copy")
      expect(frame[:srcdoc]).to include("<!DOCTYPE html>")
      # the raw markup must not be injected into the admin document itself
      expect(Nokogiri::HTML(response.body).css("section p").map(&:text)).not_to include("Body copy")
    end

    it "recompiles rich_text bodies so Lexxy tables get email-safe inline styles" do
      table_html = '<figure class="lexxy-content__table-wrapper"><table><tbody>' \
                   '<tr><th class="lexxy-content__table-cell--header"><p>H1</p></th>' \
                   '<td><p>cell</p></td></tr></tbody></table></figure>'
      tmpl = build(:email_template, :rich_text, customer: customer, subject: "Table")
      tmpl.body = table_html
      tmpl.save!
      # Simulate a row compiled before table inlining existed: stored body_html
      # is a bare table while ActionText still holds the editor source of truth.
      tmpl.update_columns(body_html: table_html)

      get "#{base_path}/#{tmpl.id}"

      frame = Nokogiri::HTML(response.body).css("iframe[sandbox]").first
      expect(frame[:srcdoc]).to include("border-collapse: collapse")
      expect(frame[:srcdoc]).to include("border: 1px solid #cecece")
      expect(frame[:srcdoc]).to include("cell")
    end

    it "rewrites cid: image sources to blob URLs in the detail iframe" do
      blob = Current.set(customer: customer) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("fake image data"),
          filename: "hero.png",
          content_type: "image/png"
        )
      end
      tmpl = create(:email_template, customer: customer, editor_type: "code",
                    body_html: %(<p>Hi</p><img src="cid:blob-#{blob.id}" alt="hero.png">))

      get "#{base_path}/#{tmpl.id}"

      frame = Nokogiri::HTML(response.body).css("iframe[sandbox]").first
      blob_url = Rails.application.routes.url_helpers.rails_blob_url(blob, only_path: true)
      expect(frame[:srcdoc]).to include(blob_url)
      expect(frame[:srcdoc]).not_to include("cid:blob-")
    end

    it "shows variable labels instead of stored UUID tokens" do
      token = platform_token("first_name")
      label = Emails::TemplateToken.platform.find_by!(uuid: platform_token_uuid("first_name")).display_label
      tmpl = create(:email_template, customer: customer, editor_type: "code",
                    subject: "Hi #{token}",
                    body_html: "<p>Dear #{token}</p>",
                    body_text: "Dear #{token}")

      get "#{base_path}/#{tmpl.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("{{#{label}}}")
      expect(response.body).not_to include(token)

      frame = Nokogiri::HTML(response.body).css("iframe[sandbox]").first
      expect(frame[:srcdoc]).to include("{{#{label}}}")
      expect(frame[:srcdoc]).not_to include(token)
    end

    it "offers Edit, Preview, Duplicate, Delete, and lifecycle status actions from the detail page" do
      tmpl = create(:email_template, customer: customer, status: "draft")

      get "#{base_path}/#{tmpl.id}"

      expect(response.body).to include(edit_admin_modules_emails_template_path(customer, tmpl))
      expect(response.body).to include(preview_admin_modules_emails_template_path(customer, tmpl))
      expect(response.body).to include(duplicate_admin_modules_emails_template_path(customer, tmpl))
      expect(response.body).to include(I18n.t("common.actions.delete"))
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.edit.delete_confirm"))

      expect(response.body).to include(I18n.t("admin_modules.emails.templates.status.actions.set_active"))
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.status.actions.set_retired"))
      expect(response.body).not_to include(I18n.t("admin_modules.emails.templates.status.actions.set_draft"))
      expect(response.body).to include(
        status_admin_modules_emails_template_path(customer, tmpl, status: "active")
      )
      expect(response.body).to include('data-turbo-method="patch"')
    end

    it "notes when there is no plain-text fallback" do
      tmpl = create(:email_template, customer: customer, body_text: nil)
      get "#{base_path}/#{tmpl.id}"
      expect(response.body).to include(I18n.t("admin_modules.emails.templates.show.plain_text_empty"))
    end

    it "returns 404 for another customer's template" do
      other_tmpl = create(:email_template, customer: other_customer)
      get "#{base_path}/#{other_tmpl.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # POST duplicate
  # ---------------------------------------------------------------------------
  describe "POST /:cid/admin/modules/emails/templates/:id/duplicate" do
    let(:template) { create(:email_template, customer: customer) }
    let(:guard_path) { "#{base_path}/#{template.id}/duplicate" }

    it_behaves_like "an admin-guarded request", :post
    it "clones the template as a draft copy and opens the copy for editing" do
      tmpl = create(:email_template, customer: customer, name: "Welcome",
                    subject: "Hello there", status: "active", editor_type: "code",
                    body_html: "<p>Original</p>")

      expect {
        post "#{base_path}/#{tmpl.id}/duplicate"
      }.to change(Emails::Template, :count).by(1)

      copy = Emails::Template.for_customer(customer).order(:created_at).last
      expect(copy.name).to eq(I18n.t("admin_modules.emails.templates.actions.duplicate_name", name: "Welcome"))
      expect(copy.subject).to eq("Hello there")
      expect(copy.body_html).to include("Original")
      expect(copy.customer_id).to eq(customer.id)
      expect(response).to redirect_to(edit_admin_modules_emails_template_path(customer, copy))
    end

    it "always lands the copy in draft so it cannot send off an active template" do
      tmpl = create(:email_template, customer: customer, status: "active")
      post "#{base_path}/#{tmpl.id}/duplicate"
      expect(Emails::Template.for_customer(customer).order(:created_at).last.status).to eq("draft")
    end

    it "carries the rich-text body across to the copy" do
      tmpl = create(:email_template, customer: customer, editor_type: "rich_text",
                    body: "<p>Rich original</p>")

      post "#{base_path}/#{tmpl.id}/duplicate"

      copy = Emails::Template.for_customer(customer).order(:created_at).last
      expect(copy.editor_type).to eq("rich_text")
      expect(copy.body.to_s).to include("Rich original")
      expect(copy.body_html).to include("Rich original")
    end

    it "leaves the source template untouched" do
      tmpl = create(:email_template, customer: customer, name: "Welcome", status: "active")
      post "#{base_path}/#{tmpl.id}/duplicate"
      expect(tmpl.reload.name).to eq("Welcome")
      expect(tmpl.status).to eq("active")
    end

    it "gives the copy its own version head so the source can still be deleted" do
      tmpl = create(:email_template, customer: customer, name: "Welcome",
                    subject: "Hello there", status: "active", editor_type: "code",
                    body_html: "<p>Original</p>")
      post "#{base_path}/#{tmpl.id}/duplicate"
      copy = Emails::Template.for_customer(customer).order(:created_at).last

      expect(copy.current_version_id).to be_present
      expect(copy.current_version_id).not_to eq(tmpl.reload.current_version_id)

      expect {
        delete "#{base_path}/#{tmpl.id}"
      }.to change(Emails::Template, :count).by(-1)
      expect(response).to redirect_to(/emails\/templates/)
      expect(Emails::Template.find_by(id: copy.id)).to be_present
    end

    it "returns 404 when duplicating another customer's template" do
      other_tmpl = create(:email_template, customer: other_customer)
      expect {
        post "#{base_path}/#{other_tmpl.id}/duplicate"
      }.not_to change(Emails::Template, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy
  # ---------------------------------------------------------------------------
  describe "DELETE /:cid/admin/modules/emails/templates/:id" do
    let(:template) { create(:email_template, customer: customer) }
    let(:guard_path) { "#{base_path}/#{template.id}" }

    it_behaves_like "an admin-guarded request", :delete
    it "destroys the template and redirects to index" do
      tmpl = create(:email_template, customer: customer)
      expect {
        delete "#{base_path}/#{tmpl.id}"
      }.to change(Emails::Template, :count).by(-1)
      expect(response).to redirect_to(/emails\/templates/)
      expect(Emails::Template.find_by(id: tmpl.id)).to be_nil
    end

    it "redirects with alert when campaigns reference the template" do
      tmpl = create(:email_template, customer: customer)
      create(:email_send_activity, customer: customer, email_template: tmpl)
      delete "#{base_path}/#{tmpl.id}"
      expect(Emails::Template.find_by(id: tmpl.id)).to be_present
      expect(response).to redirect_to(/emails\/templates/)
      follow_redirect!
      expect(response.body).to include("Cannot delete template")
    end

    it "redirects with alert when messages reference the template" do
      tmpl = create(:email_template, customer: customer)
      create(:email_message, customer: customer,
             from: "sender@example.com",
             email_template_id: tmpl.id)
      delete "#{base_path}/#{tmpl.id}"
      expect(response).to redirect_to(/emails\/templates/)
      follow_redirect!
      expect(response.body).to include("Cannot delete template")
    end

    it "returns 404 when deleting another customer's template" do
      other_tmpl = create(:email_template, customer: other_customer)
      expect {
        delete "#{base_path}/#{other_tmpl.id}"
      }.not_to change(Emails::Template, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
