# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Emails
        class TemplateTokenEditorComponent < ApplicationComponent
          def initialize(customer_id:, token:, entities:, entity_attributes:, existing_slugs: {}, submitted_fields: nil, submitted_values: nil)
            @customer_id, @token, @entities, @entity_attributes = customer_id, token, entities, entity_attributes
            @existing_slugs, @submitted_fields = existing_slugs, submitted_fields
            @submitted_values = submitted_values
          end

          attr_reader :customer_id, :token, :entities, :entity_attributes, :existing_slugs, :submitted_fields, :submitted_values

          def index_path = helpers.admin_settings_modules_emails_template_tokens_path(customer_id)
          def form_url = token.persisted? ? helpers.admin_settings_modules_emails_template_token_path(customer_id, token) : index_path
          def title = t("settings_modules.email.#{token.persisted? ? 'edit_field' : 'add_fields'}")
        end
      end
    end
  end
end
