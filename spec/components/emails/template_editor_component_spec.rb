# frozen_string_literal: true

require "rails_helper"

RSpec.describe Emails::TemplateEditorComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:url)      { "/#{customer.id}/admin/modules/emails/templates" }

  def render_editor(template:, method: :post, target_url: url)
    render_inline(
      described_class.new(
        template: template,
        url: target_url,
        method: method,
        customer_id: customer.id,
        test_recipient: "owner@example.com"
      )
    )
  end

  context "with a new template" do
    let(:template) do
      build(:email_template, customer: customer, name: nil, subject: nil,
            body_html: nil, body_text: nil, editor_type: "rich_text", status: "draft")
    end

    it "binds the workspace to the shared form id" do
      render_editor(template: template)
      expect(page).to have_css("form##{described_class::FORM_ID}[method='post']")
    end

    it "renders details, body, preview, and test cards in a split workspace" do
      render_editor(template: template)

      expect(page).to have_css("input[name='email_template[name]'][required]")
      expect(page).to have_css("input[name='email_template[subject]'][required]")
      expect(page).to have_css("lexxy-editor", visible: :all)
      expect(page).to have_css("textarea[name='email_template[body_html]']", visible: :all)
      expect(page).to have_css("textarea[name='email_template[body_text]']", visible: :all)
      expect(page).to have_css("[data-controller='remote-template-preview'] ##{described_class::PREVIEW_ANCHOR}")
      expect(page).to have_css("input#dry_run_to[type='email']")
    end

    it "isolates the live HTML preview in a sandboxed iframe" do
      render_editor(template: template)

      expect(page).to have_css("iframe[data-remote-template-preview-target='iframe'][sandbox]")
    end

    it "renders the editor mode as a segmented control backed by the visually hidden select" do
      render_editor(template: template)

      expect(page).to have_css(
        "button[data-template-editor-mode-target='modeButton'][data-mode='rich_text'][aria-pressed='true']"
      )
      expect(page).to have_css(
        "button[data-template-editor-mode-target='modeButton'][data-mode='code'][aria-pressed='false']"
      )
      expect(page).to have_css("select#email_template_editor_type.sr-only", visible: :all)
    end

    it "respects the template's activation state when rendering the checkbox" do
      render_editor(template: template)
      expect(page).to have_css("input[type='checkbox'][name='email_template[status]']:not([checked])")

      template.status = "active"
      render_editor(template: template)
      expect(page).to have_css("input[type='checkbox'][name='email_template[status]'][checked]")
    end

    # The subject field must offer token insertion by typing "{{": the wrapper
    # carries the autocomplete controller, the flattened token JSON, and the
    # translated no-matches label; the input is the controller's target.
    it "wires the subject field with the token autocomplete controller" do
      render_editor(template: template)

      wrapper = page.find("[data-controller='token-autocomplete']", visible: :all)
      expect(wrapper).to have_css("input[name='email_template[subject]'][data-token-autocomplete-target='input']")

      tokens = JSON.parse(wrapper["data-token-autocomplete-tokens-value"])
      expect(tokens).to all(include("label", "group"))
      expect(tokens.map { |t| t["label"] }).to include(Emails::TokenCatalog.for_customer(customer).platform_tokens.first.display_label)

      expect(wrapper["data-token-autocomplete-no-matches-value"]).to eq(
        I18n.t("admin_modules.emails.templates.form.token_autocomplete_no_matches")
      )
    end

    # Lexxy scopes every content style (tables, headings, lists, quotes, code,
    # highlights) under `:where(.lexxy-content)`; dropping the class off the
    # host renders block content unstyled — tables collapse to 0 width.
    it "carries lexxy-content on the rich-text editor host" do
      render_editor(template: template)
      expect(page).to have_css("lexxy-editor.lexxy-content", visible: :all)
    end

    it "renders the create submit label in the form actions" do
      render_editor(template: template)
      expect(page).to have_button(I18n.t("admin_modules.emails.templates.form.create_submit"))
    end
  end

  context "with a persisted template" do
    let!(:template) { create(:email_template, customer: customer, editor_type: "code") }

    it "points preview and test-send endpoints at the template" do
      render_editor(template: template, method: :patch, target_url: "#{url}/#{template.id}")

      workspace = page.find("[data-controller='remote-template-preview']")
      expect(workspace["data-remote-template-preview-url-value"]).to include("/templates/#{template.id}/preview")
      expect(workspace["data-remote-template-preview-test-send-url-value"]).to include("/templates/#{template.id}/test_send")
      expect(workspace["data-remote-template-preview-empty-subject-label-value"]).to eq("(Empty Subject)")
    end

    it "omits the activate-immediately checkbox and uses the update submit label" do
      render_editor(template: template, method: :patch, target_url: "#{url}/#{template.id}")

      expect(page).not_to have_css("input[type='checkbox'][name='email_template[status]']")
      expect(page).to have_button(I18n.t("admin_modules.emails.templates.form.update_submit"))
    end
  end

  context "with validation errors" do
    it "renders the shared form errors block" do
      template = build(:email_template, customer: customer, name: nil, subject: nil)
      template.valid?
      render_editor(template: template)

      expect(page).to have_css(".bg-red-50")
    end
  end

  context "with stored UUID tokens" do
    it "shows human labels in fields, never raw UUID tokens" do
      uuid = platform_token_uuid("first_name")
      label = Emails::TemplateToken.platform.find_by!(uuid: uuid).display_label
      uuid_token = "{{#{uuid}}}"
      template = build(:email_template, customer: customer,
                       subject: "Hi #{uuid_token}",
                       body_html: "<p>Dear #{uuid_token}</p>",
                       editor_type: "code")

      render_editor(template: template)

      expect(page).to have_field("email_template[subject]", with: "Hi {{#{label}}}")
      expect(page.find("textarea[name='email_template[body_html]']", visible: :all).value).to include("{{#{label}}}")
      expect(page.native.to_html).not_to include(uuid_token)
    end
  end
end
