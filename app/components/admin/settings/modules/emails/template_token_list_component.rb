# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Emails
        class TemplateTokenListComponent < ApplicationComponent
          def initialize(customer_id:, platform_tokens:, custom_tokens:)
            @customer_id, @platform_tokens, @custom_tokens = customer_id, platform_tokens, custom_tokens
          end

          attr_reader :customer_id, :platform_tokens, :custom_tokens

          def new_path = helpers.new_admin_settings_modules_emails_template_token_path(customer_id)

          def platform_description(token)
            key = case token.source_key.to_s
                  when /\Aauthentication_user\./ then "recipient_source"
                  when /\Acustomer\./ then "customer_source"
                  when "unsubscribe_url" then "unsubscribe_source"
                  else "workflow_source"
                  end
            t("settings_modules.email.#{key}")
          end

          def attribute_label(token)
            attributes = Array(token.entity&.property_schema_json)
            attribute = attributes.find { |item| (item["name_slug"] || item[:name_slug]) == token.attribute_slug }
            attribute&.dig("name").presence || attribute&.dig(:name).presence || t("settings_modules.email.unavailable_field")
          end

          def entity_label(token)
            token.entity&.display_label.presence || t("settings_modules.email.unavailable_record")
          end

          def custom_token_groups
            custom_tokens.group_by(&:entity_id)
          end
        end
      end
    end
  end
end
