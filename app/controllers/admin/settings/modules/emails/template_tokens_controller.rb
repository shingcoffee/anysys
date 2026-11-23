# frozen_string_literal: true

module Admin
  module Settings
    module Modules
      module Emails
        class TemplateTokensController < ApplicationController
          dashboard_menu_item :settings

          before_action :require_email_module!, only: %i[create update destroy]
          before_action :load_token, only: %i[edit update destroy]
          before_action :reject_platform_mutation!, only: %i[edit update destroy]

          def index
            @platform_tokens = ::Emails::TemplateToken.platform.order(:label)
            @custom_tokens = ::Emails::TemplateToken.custom_for(current_customer.id).includes(:entity).order(:label)
          end

          def new
            @token = ::Emails::TemplateToken.new(
              customer_id: current_customer.id,
              source_type: ::Emails::TemplateToken::SOURCE_ENTITY
            )
            load_entity_options
          end

          def create
            result = ::Emails::TemplateTokens::Operation::BulkCreate.call(
              customer: current_customer,
              params: bulk_token_params
            )
            if result.success?
              redirect_to admin_settings_modules_emails_template_tokens_path(current_customer.id),
                          notice: t("admin_settings.flash.email_template_tokens.created")
            else
              @token = result[:model]
              @submitted_fields = bulk_token_params[:fields]
              load_entity_options
              render :new, status: :unprocessable_entity
            end
          end

          def edit
            load_entity_options
          end

          def update
            result = ::Emails::TemplateTokens::Operation::Update.call(
              token: @token,
              params: token_params
            )
            if result.success?
              redirect_to admin_settings_modules_emails_template_tokens_path(current_customer.id),
                          notice: t("admin_settings.flash.email_template_tokens.updated")
            else
              @submitted_values = token_params.to_h
              load_entity_options
              render :edit, status: :unprocessable_entity
            end
          end

          def destroy
            result = ::Emails::TemplateTokens::Operation::Destroy.call(token: @token)
            if result.success?
              redirect_to admin_settings_modules_emails_template_tokens_path(current_customer.id),
                          notice: t("admin_settings.flash.email_template_tokens.destroyed")
            else
              redirect_to admin_settings_modules_emails_template_tokens_path(current_customer.id),
                          alert: t("admin_settings.flash.email_template_tokens.destroy_failed")
            end
          end

          private

          def require_email_module!
            return if FeatureModules::Module.enabled?(key: "email", customer_id: current_customer.id)

            head :not_found
          end

          def load_token
            @token = ::Emails::TemplateToken.accessible_for(current_customer.id).find(params[:id])
          end

          def reject_platform_mutation!
            return unless @token.platform?

            redirect_to admin_settings_modules_emails_template_tokens_path(current_customer.id),
                        alert: t("email.template_tokens.errors.platform_readonly")
          end

          def token_params
            params.require(:emails_template_token).permit(:label, :entity_id, :attribute_slug)
          end

          def bulk_token_params
            params.require(:emails_template_token).permit(:entity_id, fields: %i[attribute_slug label selected])
          end

          def load_entity_options
            @entities = Entity
              .where(customer_id: current_customer.id)
              .or(Entity.shared)
              .active
              .by_name
            @entity_attributes = @entities.each_with_object({}) do |entity, hash|
              hash[entity.id.to_s] = Array(entity.property_schema_json).filter_map do |attr|
                slug = attr["name_slug"].presence || attr[:name_slug].presence
                next if slug.blank?

                name = attr["name"].presence || attr[:name].presence || slug
                [name, slug]
              end
            end
            @existing_slugs = ::Emails::TemplateToken.custom_for(current_customer.id)
              .pluck(:entity_id, :attribute_slug).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
          end
        end
      end
    end
  end
end
