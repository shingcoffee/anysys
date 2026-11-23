# frozen_string_literal: true

module Emails
  # Create/edit workspace for an email template. Compose cards (details, body)
  # sit left; a sticky rail with live preview and test send sits right on xl
  # screens, stacking below compose on smaller screens. The page header lives
  # in AdminPageComponent and submits this form through FORM_ID; deep links to
  # the preview rail use PREVIEW_ANCHOR.
  class TemplateEditorComponent < ApplicationComponent
    FORM_ID         = "email_template_form"
    PREVIEW_ANCHOR  = "template-preview"

    attr_reader :template, :url, :method, :customer_id, :test_recipient

    def initialize(template:, url:, method:, customer_id:, test_recipient: nil)
      @template       = template
      @url            = url
      @method         = method
      @customer_id    = customer_id
      @test_recipient = test_recipient
    end

    def catalog
      @catalog ||= Emails::TokenCatalog.for_customer(customer_id)
    end

    def token_groups
      catalog.picker_groups
    end

    # Flattened [{ label:, group: }] list feeding the subject field's "{{"
    # autocomplete menu (serialised to a JSON Stimulus value in the template).
    def token_autocomplete_items
      token_groups.flat_map do |(group_label, options)|
        options.map { |(label, _value)| { label: label, group: group_label } }
      end
    end

    def preview_url
      template.persisted? ?
        preview_admin_modules_emails_template_path(customer_id, template) :
        preview_admin_modules_emails_templates_path(customer_id)
    end

    def test_send_url
      template.persisted? ?
        test_send_admin_modules_emails_template_path(customer_id, template) :
        test_send_admin_modules_emails_templates_path(customer_id)
    end

    # The editor must never show storage UUIDs — only human labels. The persist
    # path (model normalize via TemplateTokenCodec) rewrites back to {{uuid}}.
    def rich_body_value
      source = template.body.present? ? template.body.to_trix_html.to_s : template.body_html.to_s
      labeled(source)
    end

    def labeled(value)
      Emails::TemplateTokenCodec.tokens_to_labels(value, catalog: catalog)
    end

    def rich_mode?
      template.editor_type == "rich_text"
    end

    def mode_button_classes(type)
      base = "rounded-md px-3 py-1.5 text-sm font-medium transition-base cursor-pointer"
      if template.editor_type == type
        "#{base} bg-surface text-text-primary shadow-sm"
      else
        "#{base} text-text-secondary hover:text-text-primary"
      end
    end
  end
end
