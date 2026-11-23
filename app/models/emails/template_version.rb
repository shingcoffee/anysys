# frozen_string_literal: true

module Emails
  class TemplateVersion < ApplicationRecord
    self.table_name = "email_template_versions"
    include VersionRecord

    acts_as_version parent: :email_template, parent_class_name: "Emails::Template",
                    content_class: "Emails::TemplateContent"

    # Parsed definition payload (subject/body_html/body_text/editor_type/body_raw).
    def payload_json
      JSON.parse(payload.presence || "{}")
    end
  end
end
