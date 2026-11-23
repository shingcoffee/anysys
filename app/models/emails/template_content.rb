# frozen_string_literal: true

# Content-addressed store for Emails::Template definition snapshots
# (subject/body_html/body_text/editor_type/body_raw). See ContentAddressable.
module Emails
  class TemplateContent < ApplicationRecord
    self.table_name = "email_template_contents"
    include ContentAddressable

    has_many :template_versions, class_name: "Emails::TemplateVersion",
             foreign_key: :content_id, inverse_of: :content, dependent: :restrict_with_exception

    def self.version_association = :template_versions
  end
end
