# frozen_string_literal: true

module Admin
  module Maintenance
    module Platform
      # Abstract base for platform-wide, vendor-keyed credential CRUD (email SMTP/DKIM,
      # SMS). Exposed under the platform owner's tenant per the four-part module URL
      # rule (AGENTS.md, module category d). Subclasses declare the model, persistence
      # Activity, provider registry, flash scope, and index route via
      # `manages_credentials`, and provide the vendor-specific `index_columns` and
      # `credential_params`.
      class BaseCredentialsController < ApplicationController
        include Listable
        dashboard_menu_item :maintenance

        before_action :set_credential, only: %i[edit update]

        class_attribute :credential_model, :save_activity, :provider_registry,
                        :flash_scope, :index_route

        # The `index_route` lambda runs in controller context (it can read
        # `current_customer_id`), mirroring BaseRestorationsController#restorable.
        def self.manages_credentials(model:, activity:, registry:, flash_scope:, index_route:)
          self.credential_model  = model
          self.save_activity     = activity
          self.provider_registry = registry
          self.flash_scope       = flash_scope
          self.index_route       = index_route
        end

        def index
          @columns = index_columns
          result   = listable(credential_model.all.order(created_at: :desc), columns: @columns)
          @rows       = result[:rows]
          @pagination = result[:pagination]
        end

        def new
          @credential = credential_model.new(provider: provider_registry.default_key.to_s, mode: "sandbox")
        end

        def create
          @credential = credential_model.new
          persist(:created) { render :new, status: :unprocessable_entity }
        end

        def edit; end

        def update
          persist(:updated) { render :edit, status: :unprocessable_entity }
        end

        private

        def persist(flash_key)
          result = save_activity.call(record: @credential, params: credential_params)
          if result.success?
            redirect_to index_path, notice: t("maint_platform.flash.#{flash_scope}.#{flash_key}")
          else
            yield
          end
        end

        def index_path
          instance_exec(&index_route)
        end

        # Human-readable provider name from the vendor registry, falling back to a
        # titleized key for an unknown provider.
        def provider_display_name(provider)
          provider_registry.for(provider).display_name
        rescue ArgumentError
          provider.to_s.titleize
        end

        # Columns every vendor-keyed credential table shares; subclasses splice
        # vendor-specific columns between them in `index_columns`.
        def provider_column
          { key: :provider, label: I18n.t("common.labels.provider"), type: :badge, sortable: true,
            badge: ->(c) { { variant: :default, label: provider_display_name(c.provider) } },
            cell:  ->(c) { provider_display_name(c.provider) } }
        end

        def mode_column
          { key: :mode, label: I18n.t("common.labels.mode"), type: :badge, sortable: true,
            badge: ->(c) { { variant: :default, label: I18n.t("common.modes.#{c.mode}") } },
            cell:  ->(c) { I18n.t("common.modes.#{c.mode}") } }
        end

        def status_column
          { key: :status, label: I18n.t("common.labels.status"), type: :badge, sortable: true,
            badge: ->(c) { { variant: c.status == "active" ? :success : :default, label: I18n.t("common.status.#{c.status}") } },
            cell:  ->(c) { I18n.t("common.status.#{c.status}") } }
        end

        def created_at_column
          { key: :created_at, label: I18n.t("common.labels.created_at"), type: :datetime, sortable: true }
        end

        def set_credential
          @credential = credential_model.find(params[:id])
        end

        # Vendor-specific — subclasses must implement.
        def index_columns
          raise NotImplementedError, "#{self.class} must implement #index_columns"
        end

        def credential_params
          raise NotImplementedError, "#{self.class} must implement #credential_params"
        end
      end
    end
  end
end
