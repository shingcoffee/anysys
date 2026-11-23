Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  #
  # ============================================================================
  # URL Categorization (per AGENTS.md)
  # ============================================================================
  # Every URL in this file MUST fall into exactly one of three categories:
  #
  #   a) Admin       — /:cid/admin/...        (admin or owner role)
  #   b) Member — /:cid/member/...  (member role)
  #   c) Public      — anything else          (no auth required)
  #
  # The file below is grouped accordingly:
  #
  #   1. PUBLIC       — top-level public endpoints (root, sign-in, webhooks,
  #                     unsubscribe, health check)
  #   2. TENANT-SCOPED — everything under /:customer_id, sub-grouped into:
  #        2a. Public        — auth/MFA, public forms, payment checkout
  #        2b. Admin         — /:cid/admin/...
  #        2c. Member   — /:cid/member/...   (none yet — placeholder)
  #
  # When adding a new URL, place it under the correct group above.
  # ============================================================================

  # ==========================================================================
  # 1. PUBLIC (top-level, no tenant scope)
  # ==========================================================================

  # Health check — returns 200 if the app boots cleanly.
  get "up" => "rails/health#show", as: :rails_health_check

  get  "/captcha/challenge", to: "captcha/challenges#show", as: :captcha_challenge
  post "/captcha/challenge", to: "captcha/challenges#create"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Clean URLs dispatch to existing public controllers. Resolve only at request
  # time, including explicit root mappings to an inner website or public Page.
  public_shortcut_destinations = [
    ["websites/pages", "home"],
    ["websites/pages", "show"],
    ["public_pages", "show"]
  ]
  public_shortcut_destinations.each do |controller, action|
    get "/", to: "#{controller}##{action}", format: false,
        constraints: ->(request) { PageShortcuts::RouteConstraint.matches?(request, controller: controller, action: action) }
  end

  get "/", to: "page_shortcuts/unavailable#show", format: false,
      constraints: ->(request) { PageShortcuts::Resolver.unavailable_root?(request) }

  # Keep one named root helper and the existing sign-in/landing fallback only
  # for genuinely unmapped roots without a published home, including shared-host
  # bootstrap before the default customer exists.
  root "home#index"

  # OAuth 2.0 + PKCE for the first-party desktop GUI (public client).
  # Authorize is a browser page that reuses Devise + MFA; token/revoke/userinfo
  # authenticate with PKCE / Bearer, not cookies. See docs/guides/OAUTH_PKCE_DESKTOP.md.
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications, :token_info
    controllers authorizations: "oauth/authorizations", tokens: "oauth/tokens"
  end
  get "/.well-known/oauth-authorization-server", to: "oauth/discovery#show",
      as: :oauth_authorization_server
  get "/oauth/userinfo", to: "oauth/userinfo#show", as: :oauth_userinfo

  # UI language switch (public — anonymous users may switch too). Persists to
  # the signed-in user's preference and always to a cookie, then redirects back.
  patch "/locale", to: "locales#update", as: :locale

  # Payment PSP webhooks (tenant resolved via payload merchant_id).
  #
  # The provider constraint is evaluated at request time (lambda) rather than
  # route-draw time so that:
  #   a) adding a new gateway file (the ONLY required change per AGENTS.md) is
  #      automatically reflected without touching routes.rb at all; and
  #   b) there is no eager-load / boot-order risk — Payments::Gateways.keys
  #      calls load_all internally and is safe to invoke after the app boots.
  #
  # Implementation note: inside a lambda constraint, path parameters have not
  # been extracted yet, so req.params[:provider] is always nil. We extract the
  # provider segment directly from req.path_info instead.
  post "/payments/webhooks/:provider",
       to: "payments/webhooks#create",
       as: :payments_webhook,
       constraints: ->(req) {
         provider = req.path_info.match(%r{\A/payments/webhooks/([^/.]+)(?:\.[^/]+)?\z})&.[](1)
         Payments::Gateways.keys.map(&:to_s).include?(provider)
       }

  # SMS vendor callbacks (delivery receipts + inbound STOP). No auth; trust via
  # per-adapter signature verification. Provider constraint evaluated at request
  # time so adding an adapter file needs no routes.rb change.
  post "/sms/webhooks/:provider/:kind",
       to: "sms/webhooks#create",
       as: :sms_webhook,
       constraints: ->(req) {
         provider = req.path_info.split("/")[3]
          Sms::Adapters.keys.map(&:to_s).include?(provider)
       }

  # Browser confirmation only: signed destination, read-only GET, CSRF-protected POST.
  get  "/sms/unsubscribes/:token", to: "sms/unsubscribes#show", as: :sms_unsubscribe
  post "/sms/unsubscribes/:token", to: "sms/unsubscribes#create"

  # Email provider callbacks (delivery / bounce / complaint). No auth; trust via
  # per-provider signature/basic-auth verification. Provider constraint at
  # request time so adding a provider file needs no routes.rb change.
  post "/email/webhooks/:provider",
       to: "emails/webhooks#create",
       as: :email_webhook,
       constraints: ->(req) {
         provider = req.path_info.match(%r{\A/email/webhooks/([^/.]+)(?:\.[^/]+)?\z})&.[](1)
         Email::Providers.keys.map(&:to_s).include?(provider)
       }

  get "/email/track/:message_id/open.gif", to: "emails/tracking#open", as: :email_track_open
  get "/email/track/:message_id/click",    to: "emails/tracking#click", as: :email_track_click

  # Email send-activity unsubscribe (no auth, no tenant scope)
  get  "/unsubscribe/:token", to: "emails/unsubscribes#show",   as: :email_unsubscribe
  post "/unsubscribe/:token", to: "emails/unsubscribes#create", as: :email_unsubscribe_create

  # ==========================================================================
  # 2. TENANT-SCOPED ROUTES — /:customer_id/...
  # ==========================================================================
  # All tenant resources are nested under /:customer_id (8-digit tenant ID).
  #
  # @example
  #   GET /12345678/admin/maintenance/flowcharts        -> admin maintenance
  #   GET /12345678/admin/maintenance/entities          -> admin maintenance
  #   GET /12345678/admin/maintenance/flowcharts/1/edit -> admin maintenance
  # ==========================================================================

  # ----- Devise (public; email is globally unique so no tenant in the path) -----
  devise_for :users, path: "auth",
    class_name: "Authentication::User",
    skip: [:registrations, :unlocks],
    controllers: {
      sessions: "authentication/sessions",
      passwords: "authentication/passwords",
      confirmations: "authentication/confirmations"
    }

  # Public customer (tenant) sign-up is unscoped. Member sign-up still
  # joins a specific tenant. Account edit is session-scoped.
  devise_scope :user do
    get  "/auth/sign_up",
         to: "authentication/customer_registrations#new",
         as: :new_customer_registration
    post "/auth/sign_up",
         to: "authentication/customer_registrations#create",
         as: :customer_registration
    get  "/auth/sign_up/check_email",
         to: "authentication/customer_registrations#check_email",
         as: :customer_registration_check_email
    post "/auth/sign_up/resend",
         to: "authentication/customer_registrations#resend",
         as: :customer_registration_resend
    get  "/auth/sign_up/confirm",
         to: "authentication/customer_registrations#confirm",
         as: :customer_registration_confirm
    post "/auth/sign_in_link",
         to: "authentication/sign_in_links#create",
         as: :sign_in_links
    get  "/auth/sign_in_link/check_email",
         to: "authentication/sign_in_links#check_email",
         as: :sign_in_link_check_email
    get  "/auth/sign_in_link",
         to: "authentication/sign_in_links#show",
         as: :sign_in_link
    get  "/:customer_id/auth/sign_up",
         to: "authentication/registrations#new",
         as: :new_user_registration,
         constraints: { customer_id: /\d{8}/ }
    post "/:customer_id/auth",
         to: "authentication/registrations#create",
         as: :tenant_user_registration,
         constraints: { customer_id: /\d{8}/ }
    get  "/auth/edit",
         to: "authentication/registrations#edit",
         as: :edit_user_registration
    match "/auth",
          to: "authentication/registrations#update",
          via: [:put, :patch],
          as: :user_registration
  end

  scope "/:customer_id", constraints: { customer_id: /\d{8}/ } do
    # ========================================================================
    # 2a. PUBLIC (tenant-scoped, no role required)
    # ========================================================================

    # MFA / 2FA (auth surface)
    scope "auth" do
      resource :mfa_setup,    only: %i[show create], controller: "authentication/mfa_setups",     path: "mfa/setup"
      resource :mfa_session,  only: %i[show create], controller: "authentication/mfa_sessions",   path: "mfa/session"
      resource :mfa,          only: :destroy,        controller: "authentication/mfas",           path: "mfa"
      resource :mfa_recovery, only: %i[new create],  controller: "authentication/mfa_recoveries", path: "mfa_recovery" do
        get  :consume, on: :collection
        post :consume, on: :collection
      end
    end

    # Public page surface
    page_uuid = /[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/i
    get  "page/:uuid", to: "public_pages#show",   as: :public_page,        constraints: { uuid: page_uuid }
    post "page/:uuid", to: "public_pages#submit", as: :public_page_submit, constraints: { uuid: page_uuid }
    get  "actions/:action_key", to: "pages/actions#show", as: :page_action,
         constraints: { action_key: /[a-z][a-z0-9_]{1,62}/ }
    get  "journeys/:key", to: "journeys/starts#show", as: :journey_start,
         constraints: { key: /[a-z][a-z0-9_]{1,62}/ }

    # Website module public marketing site (GET only — no public POST)
    get "site", to: "websites/pages#home", as: :website_home
    get "site/media/:signed_id", to: "websites/assets#show", as: :website_media,
        constraints: { signed_id: /[^\/]+/ }
    get "site/:page_slug", to: "websites/pages#show", as: :website_page,
        constraints: { page_slug: /[a-z0-9]+(?:-[a-z0-9]+)*/ }

    # Page → module handoff hop: leaves Turbo Drive, collects the end user's
    # user_fillable inputs, then enters the module's entry_path.
    resource :handoff, only: %i[show update], controller: "feature_modules/handoffs",
                       as: :feature_module_handoff

    # Payment public flow (customer checkout + result page)
    scope "payments" do
      get  "checkout/start",      to: "payments/checkouts#start",  as: :payment_checkout_start
      get  "checkout",            to: "payments/checkouts#show",   as: :payment_checkout
      post "checkout",            to: "payments/checkouts#create", as: :payment_checkout_create
      get  ":id/status",          to: "payments/checkouts#status", as: :payment_status
      get  "result/:payment_id",  to: "payments/results#show",     as: :payment_result
    end

    # ========================================================================
    # 2b. ADMIN — /:cid/admin/...   (admin or owner role required)
    # ========================================================================
    namespace :admin do
      # Admin namespace root is the AI Assistant (signed-in default landing).
      # Home remains GET /:cid/admin/dashboard; the tab URL is /:cid/admin/assistant.
      root to: "assistants#show"
      resource :dashboard, only: :show, controller: "dashboards"
      get "assistant", to: "assistants#show", as: :assistant

      # Session dismiss for the admin-chrome banner. Tenant admins must be able
      # to POST this; do not nest it under /admin/maintenance/platform/.
      resources :platform_announcement_dismissals, only: [:create]

      # Per-user mark-read for the admin-chrome notification bell. Same tenant
      # admin prefix as dismissals — not /admin/maintenance/platform/.
      resources :platform_announcement_reads, only: [:create]
      # Per-user mark-read for help tickets in the same bell. Full-page POST
      # then redirect to the thread — not nested under platform maintenance.
      resources :support_ticket_reads, only: [:create]

      resources :support_tickets, only: %i[show create] do
        resources :messages, only: :create, controller: "support_ticket_messages"
      end
      resources :help_emails, only: :create

      namespace :help do
        resources :docs, only: %i[index show], param: :slug,
                  constraints: { slug: /[a-z0-9]+(?:-[a-z0-9]+)*/ }
      end

      # Desktop PKCE Bearer API — entity definition list (not entries).
      resources :entity_definitions, only: :index

      # Desktop PKCE Bearer API — AI assistant (typed wording + STT poll).
      # Cookie composer stays under modules/ai_assistant; these reject cookies.
      namespace :assistant do
        resources :messages, only: %i[index create]
        resources :transcriptions, only: %i[create show]
      end

      # ---- Browse views and entity entry actions ----
      # The customer's entities and their forms, one domain at a time (:id is
      # a domain id or "ungrouped"); the index shows the first domain. Forms
      # are listed per domain and per entity; a single form keeps its shallow
      # /pages/:id routes.
      resources :domains, only: %i[index show] do
        resources :pages, only: :index, module: :domains
      end
      resources :entities, only: :show do
        resources :pages, only: :index, module: :entities
        # The entity's launched page renders new and edit and submits to its
        # own public endpoint, so there are no create / update actions.
        resources :entries, only: %i[new show edit destroy], controller: "entity_entries" do
          collection do
            delete :batch, action: :batch_destroy
          end
          # Bridge rows linking this entry to an associated entity; the
          # association is named by its bridge entity id.
          resources :associations, only: [] do
            resources :entries, only: %i[new create edit update destroy], controller: "entity_association_entries"
          end
          resource :person_link, only: :create, controller: "entity_entry_person_links" do
            get :candidates
          end
          # Starts a launched journey that begins from this record.
          post "journeys/:key", to: "entity_entry_journeys#create", as: :journey
        end
        resource :index_setting, only: :update, controller: "entity_index_settings"
      end

      resources :pages, only: :show do
        collection do
          patch :batch, action: :batch_update
        end
      end

      resources :modules, only: :index, param: :key do
        resources :entries, only: :show, param: :key, controller: "module_entries"
      end
      get "modules/:module_key/howto", to: "module_howtos#show", as: :module_howto

      # ---- Settings landing ----
      resource :setting, only: :show, controller: "settings", path: "settings"

      # ---- Per-module customer settings (Module category b) ----
      # Must come BEFORE the generic `settings/modules/:module_key` route below,
      # otherwise that route swallows `payments/merchant_accounts` etc. as the module_key.
      namespace :settings do
        resource :member, only: %i[show update] do
          resources :sources,  only: %i[show update],
                               param:  :key,
                               controller: "member_sources" do
            resources :surfaces, only: %i[show update],
                                 param:  :key,
                                 controller: "member_surfaces"
          end
        end

        namespace :modules do
          namespace :payments do
            resources :merchant_accounts, only: %i[index new create edit update] do
              member { post :test_connection }
            end
            resource :default_gateway, only: :update, controller: "default_gateways"
          end
          namespace :authentication do
            resources :roles do
              resource :grants, only: %i[show update], controller: "role_grants"
            end
            resources :user_role_assignments, only: %i[index create destroy]
            resource :sign_up, only: %i[show update], controller: "sign_up"
            resource :forget_password, only: %i[show update], controller: "forget_password"
          end
          namespace :captcha do
            # Sidebar /:cid/admin/settings/modules/captcha — must stay ahead of
            # generic module_configs so StatusController wins over :key.
            get "/", to: "status#show"
            resource :status, only: :show, controller: "status"
            resources :pages, only: :update
          end
          namespace :emails do
            resources :template_tokens, only: %i[index new create edit update destroy]
          end
          namespace :website do
            get "/", to: "sites#show"
            resource :site, only: %i[show update], controller: "sites"
            resource :skeleton, only: :create, controller: "skeletons"
          end
        end

        namespace :billing do
          # Sidebar /:cid/admin/settings/billing — must stay ahead of nested
          # billing resources so SubscriptionsController wins the collection root.
          get "/", to: "subscriptions#show"
          resource :subscription, only: %i[show update], controller: "subscriptions" do
            get :plan_change_preview, on: :member
            resource :plan_change, only: :destroy, controller: "plan_changes"
            resource :one_time_payment, only: :create, controller: "subscription_one_time_payments"
          end
          resource  :cancellation,      only: %i[create destroy]
          resource  :coupon_redemption, only: :create
          resources :payment_methods,   only: %i[index create destroy] do
            collection { post :setup_intent }
            member do
              patch :make_default
              get :authorization
              post :confirmation
            end
          end
          resources :invoices, only: %i[index show] do
            member { get :download }
            resource :payment, only: :create, controller: "invoice_payments"
            resource :one_time_payment, only: %i[show create], controller: "one_time_payments" do
              get :status
              post :confirm
            end
          end
        end
      end

      resources :module_configs, only: %i[show update], param: :key,
        path: "settings/modules" do
        get ":entry_key", on: :member, action: :show, as: :entry
      end

      # ---- Search ----
      get "search", to: "search#index", as: :search

      # ====================================================================
      # Maintenance (admin/owner) — /:cid/admin/maintenance/...
      # ====================================================================
      resource :maintenance, only: :show, controller: "maintenances"
      scope :maintenance, as: :maintenance do
        resource :customer_profile, only: [:show, :edit, :update], controller: "maintenance/customer_profiles"

        resources :page_shortcuts, only: %i[index create update destroy], controller: "maintenance/page_shortcuts"

        # Constants management
        resources :constants, controller: "maintenance/constants" do
          resource :copy, only: :show, controller: "maintenance/constant_copies"
          resource :override, only: :destroy, controller: "maintenance/shared_resource_overrides"
        end

        # Module enable/disable (Module category c)
        resources :modules, only: [:index], controller: "maintenance/modules" do
          resource :enablement, only: %i[create destroy], controller: "maintenance/module_enablements"
          resource :sub_toggle, only: [:update], controller: "maintenance/module_sub_toggles"
          resource :owner_configuration, only: [:update], controller: "maintenance/module_owner_configurations"
        end

        # Entity management (full CRUD)
        resources :entities, controller: "maintenance/entities" do
          resource :restoration,     only: :update, controller: "maintenance/entity_restorations"
          resource :copy,             only: :show,  controller: "maintenance/entity_copies"
          resource :template_preview, only: :show,  controller: "maintenance/entity_template_previews"
          # Drop this customer's override of a shared entity (revert to default).
          resource :override,         only: :destroy, controller: "maintenance/shared_resource_overrides"
          # Move the entity between domains (platform owner only).
          resource :domain_membership, only: %i[edit update], controller: "maintenance/entity_domain_memberships"
          resources :versions, only: %i[index show create edit destroy],
                    controller: "maintenance/entity_versions" do
            member do
              put :default
              post :page
            end
          end
          collection do
            get :trash
            delete :empty_trash
            get :template_fields
            get :base_model_fields
            # Journeys (platform owner only — OwnerOnlySurfaces). Customer-owned,
            # so not remounted under platform.
            resources :journeys, except: %i[index show], controller: "maintenance/journeys" do
              resource :launch, only: %i[create destroy], controller: "maintenance/journey_launches"
              resource :copy, only: :create, controller: "maintenance/journey_copies"
              collection do
                get :generate, to: "maintenance/journey_generations#new"
                post :generate, to: "maintenance/journey_generations#create"
              end
            end
          end
        end

        # Entity domains (platform owner only — OwnerOnlySurfaces)
        resources :entity_domains, only: %i[new create edit update destroy],
                  controller: "maintenance/entity_domains"

        # Template picker cards (lazy-loaded grid for entity form + page builder)
        resource :template_picker_cards, only: :show,
                 controller: "maintenance/template_picker_cards"

        # Full preview of a layout template by key (no persisted entity required)
        resources :template_previews, only: :show,
                  controller: "maintenance/template_previews"

        # Flowcharts CRUD
        resources :flowcharts, controller: "maintenance/flowcharts" do
          resource :restoration, only: :update, controller: "maintenance/flowchart_restorations"
          resource :copy,        only: :show,   controller: "maintenance/flowchart_copies"
          resource :override,    only: :destroy, controller: "maintenance/shared_resource_overrides"
          collection do
            get :trash
            delete :empty_trash
            # Read-only I/O inspection for tenant editors. POST transports the
            # in-progress config; the actions do not execute generated code.
            post "step_actions/:generator_action/io_params",
              to: "maintenance/flowcharts/step_io_params#show",
              as: :step_io_params,
              constraints: { generator_action: /[A-Za-z0-9_]+/ }
            post "element_types/:element_type/io_params",
              to: "maintenance/flowcharts/element_io_params#show",
              as: :element_io_params,
              constraints: { element_type: /[A-Za-z0-9_]+/ }
            # Searchable reference pickers for the step form. JSON only;
            # owner-gated with the rest of the flowchart editor.
            get "reference_options/:source",
              to: "maintenance/flowchart_reference_options#show",
              as: :reference_options,
              constraints: { source: /[a-z][a-z0-9_]*/ }
            scope :validation, as: :validation do
              resource :implicit_keys, only: :show, controller: "maintenance/flowcharts/implicit_keys"
            end
          end
          resources :versions, only: %i[index show create edit destroy], controller: "maintenance/flowchart_versions" do
            member { put :default }
          end
          resource :launch, only: %i[create destroy], controller: "maintenance/flowchart_launches"
          # Stateless server-side validation for the editor's Validate button
          # (admin area — guarded centrally by RouteAuthorization)
          resource :validation, only: :create, controller: "maintenance/flowcharts/validations"
          resources :traces, only: :create, controller: "maintenance/flowchart_traces"
          resource :document, only: :show, controller: "maintenance/flowchart_documents"
        end

        # Pages management (full CRUD)
        resources :pages, controller: "maintenance/pages" do
          resource :restoration,          only: :update, controller: "maintenance/page_restorations"
          resource :visibility,           only: :update, controller: "maintenance/page_visibilities"
          # The flowchart that processes the page's submissions (platform owner
          # only — FlowchartVisibility gates the flowchart_bindings controller).
          resource :flowchart,            only: :update, controller: "maintenance/flowchart_bindings"
          resource :override,             only: :destroy, controller: "maintenance/shared_resource_overrides"
          resources :versions, only: %i[index show create edit destroy],
                    controller: "maintenance/page_versions" do
            member { put :default }
          end
          resource :copy,                 only: :show,   controller: "maintenance/page_copies"
          resource :template_application, only: :create, controller: "maintenance/page_template_applications"
          collection do
            get :trash
            delete :empty_trash
            resources :field_templates, only: [:index, :create, :update, :destroy], controller: "maintenance/field_templates"
          end
          resource :launch, only: %i[create destroy], controller: "maintenance/page_launches"
          resource :preview, only: %i[show create], controller: "maintenance/page_previews"
          resource :render,  only: :show,          controller: "maintenance/page_renders"
          resources :field_options, only: :show, param: :field_id, controller: "maintenance/page_field_options"
          resources :module_data, only: :show, param: :module_id, controller: "maintenance/page_module_data"
        end

        # ==================================================================
        # Platform tools — platform owner customer (81721200) only
        # ==================================================================
        scope "platform", as: :platform do
          # Shared Resources — same controllers as tenant maintenance; identity
          # (customer_id NULL) is forced by SharedResourceMode. Entity entries
          # are not remounted: they remain tenant data.
          resources :constants, controller: "maintenance/constants" do
            resource :copy, only: :show, controller: "maintenance/constant_copies"
          end

          resources :entities, controller: "maintenance/entities" do
            resource :restoration,     only: :update, controller: "maintenance/entity_restorations"
            resource :copy,             only: :show,  controller: "maintenance/entity_copies"
            resource :template_preview, only: :show,  controller: "maintenance/entity_template_previews"
            resources :versions, only: %i[index show create edit destroy],
                      controller: "maintenance/entity_versions" do
              member do
                put :default
                post :page
              end
            end
            collection do
              get :trash
              delete :empty_trash
              get :template_fields
              get :base_model_fields
            end
          end

          resources :flowcharts, controller: "maintenance/flowcharts" do
            resource :restoration, only: :update, controller: "maintenance/flowchart_restorations"
            resource :copy,        only: :show,   controller: "maintenance/flowchart_copies"
            collection do
              get :trash
              delete :empty_trash
              get "reference_options/:source",
                to: "maintenance/flowchart_reference_options#show",
                as: :reference_options,
                constraints: { source: /[a-z][a-z0-9_]*/ }
              scope :validation, as: :validation do
                resource :implicit_keys, only: :show, controller: "maintenance/flowcharts/implicit_keys"
              end
            end
            resources :versions, only: %i[index show create edit destroy], controller: "maintenance/flowchart_versions" do
              member { put :default }
            end
            resource :launch, only: %i[create destroy], controller: "maintenance/flowchart_launches"
            resource :validation, only: :create, controller: "maintenance/flowcharts/validations"
            resources :traces, only: :create, controller: "maintenance/flowchart_traces"
            resource :document, only: :show, controller: "maintenance/flowchart_documents"
          end

          resources :pages, controller: "maintenance/pages" do
            resource :restoration,          only: :update, controller: "maintenance/page_restorations"
            resource :visibility,           only: :update, controller: "maintenance/page_visibilities"
            resource :flowchart,            only: :update, controller: "maintenance/flowchart_bindings"
            resources :versions, only: %i[index show create edit destroy],
                      controller: "maintenance/page_versions" do
              member { put :default }
            end
            resource :copy,                 only: :show,   controller: "maintenance/page_copies"
            resource :template_application, only: :create, controller: "maintenance/page_template_applications"
            collection do
              get :trash
              delete :empty_trash
            end
            resource :launch, only: %i[create destroy], controller: "maintenance/page_launches"
            resource :preview, only: %i[show create], controller: "maintenance/page_previews"
            resource :render,  only: :show,          controller: "maintenance/page_renders"
            resources :field_options, only: :show, param: :field_id, controller: "maintenance/page_field_options"
            resources :module_data, only: :show, param: :module_id, controller: "maintenance/page_module_data"
          end

          resources :customers, controller: "maintenance/platform/customers" do
            # Member :id, not a second :customer_id. The outer tenant segment
            # is already :customer_id; reusing that name makes the URL helper
            # drop the trashed customer into the format extension.
            member do
              patch :restoration, to: "maintenance/platform/customer_restorations#update"
            end
            collection do
              get :trash
              delete :empty_trash
            end
          end

          resources :support_tickets, controller: "maintenance/platform/support_tickets", only: %i[index show] do
            resources :messages, only: :create, controller: "maintenance/platform/support_ticket_messages"
            resource :resolution, only: :create, controller: "maintenance/platform/support_ticket_resolutions"
          end

          resources :announcements, controller: "maintenance/platform/announcements" do
            # In-form audience sizing: POST because the segment AST is posted as
            # a body, not because it mutates anything.
            post :audience_preview, on: :collection
          end

          # Module settings (platform-wide config index + per-module surfaces)
          # — Module category d.
          #
          # Every surface is a real, bookmarkable path whose first segment is the
          # module key, so the URL vocabulary matches FeatureModules::Module#key
          # everywhere and the section tabs are links rather than `?tab=` state:
          #
          #   /module_settings                            module catalog
          #   /module_settings/:key                       Overview
          #   /module_settings/:key/configuration         Configuration
          #   /module_settings/:key/developer             Developer
          #   /module_settings/email/credentials          Providers   (email)
          #   /module_settings/sms/credentials            Providers   (sms)
          #   /module_settings/sms/templates              Resources   (sms)
          #   /module_settings/captcha/settings           Providers   (captcha)
          #   /module_settings/captcha/pages              Resources   (captcha)
          #   /module_settings/ai_assistant/settings    Providers   (ai_assistant)
          #   /module_settings/payment/gateways           Providers   (payment)
          #   /module_settings/payment/webhook_events     Operations  (payment)
          resources :module_settings, controller: "maintenance/platform/module_settings", only: [:index, :show, :update] do
            member do
              get :configuration
              get :developer
            end
          end

          # Per-module platform settings (path nested under module_settings; helpers
          # generated directly without redundant prefix to avoid `module_settings_module_settings_*`).
          # The namespace segment is the module key, never its plural.
          scope :module_settings, as: :module_settings do
            namespace :email, module: "maintenance/platform/emails" do
              resources :credentials, only: %i[index new create edit update] do
                patch :delivery, on: :collection
              end
            end
            namespace :sms, module: "maintenance/platform/sms" do
              resources :credentials, only: %i[index new create edit update] do
                patch :delivery, on: :collection
              end
              resources :templates,   only: %i[index new create edit update destroy]
            end
            namespace :captcha, module: "maintenance/platform/captcha" do
              resource :settings, only: %i[show edit update] do
                post :test_connection
              end
              # Per-surface URL throttles. Helper:
              # admin_maintenance_platform_module_settings_captcha_surfaces_path(cid)
              resource :surfaces, only: :update
              resources :pages, only: %i[index update]
            end
            namespace :ai_assistant, module: "maintenance/platform/ai_assistant" do
              resource :settings, only: %i[show edit update] do
                post :test_connection
              end
            end
            namespace :payment, module: "maintenance/platform/payments" do
              resources :gateways, only: %i[index update], param: :provider, controller: "platform_gateways"
              # Platform-owner cross-tenant ledger of inbound PSP webhook events,
              # with a per-event redrive (re-enqueue processing). Global because a
              # webhook is recorded before its tenant is resolved (customer_id is
              # nil for exactly the received/failed events that need redriving).
              resources :webhook_events, only: :index do
                member { post :redrive }
              end
            end
            namespace :website, module: "maintenance/platform/website" do
              get "skeletons", to: "skeletons#show", as: :skeletons
              get "skeletons/:key/edit", to: "skeletons#edit", as: :edit_skeleton
              get "skeletons/:key/preview", to: "skeletons#preview", as: :preview_skeleton
              patch "skeletons/:key", to: "skeletons#update", as: :skeleton
              resources :layouts, param: :key, only: %i[index new create edit update] do
                member { get :preview }
              end
            end
          end

          # First-class platform billing area (not nested under module_settings)
          namespace :billing, module: "maintenance/platform/billing" do
            resources :plans
            resource  :countable_items, only: %i[show update], controller: "countable_items"
            resources :coupons
            resources :subscriptions, only: %i[index show] do
              resource :cancellation, only: :create
            end
            resources :invoices, only: %i[index show] do
              member { post :mark_paid; post :void; post :retry }
            end
            resource :settings, only: %i[show edit update]
          end

          # Industry templates
          resources :industry_templates, controller: "maintenance/platform/industry_templates", only: %i[index show edit update] do
            resources :template_assignments, only: %i[create destroy],
              controller: "maintenance/platform/industry_template_assignments"
            resource :template_cards, only: :show,
              controller: "maintenance/platform/industry_template_cards"
            collection do
              resource :default_seed, only: %i[create destroy],
                controller: "maintenance/platform/industry_template_default_seeds"
              resource :new_template_seed, only: :create,
                controller: "maintenance/platform/industry_template_new_template_seeds"
            end
          end

          # Code generators
          resources :code_generators, controller: "maintenance/platform/code_generators",
                    param: :slug, constraints: { slug: %r{[^.]+} } do
            resource :validation, only: :create, controller: "maintenance/platform/code_generators/validations"
            resource :preview,    only: :show,   controller: "maintenance/platform/code_generators/previews"
            resource :test_run,   only: :create, controller: "maintenance/platform/code_generators/test_runs"
            collection do
              resource :source_preview, only: :create, controller: "maintenance/platform/code_generators/source_previews"
            end
          end

          # Platform code generator IO inspection APIs.
          # Platform-owner only, like every other code-generator endpoint.
          post "code_generators/:generator_action/io_params",
            to: "maintenance/platform/code_generators/io_params#show",
            as: :code_generator_io_params,
            constraints: { generator_action: /[A-Za-z0-9_]+/ }
          post "code_generators/element_types/:element_type/io_params",
            to: "maintenance/platform/code_generators/element_type_io_params#show",
            as: :code_generator_element_type_io_params,
            constraints: { element_type: /[A-Za-z0-9_]+/ }

          # Developer reference. Markdown in doc/reference is rendered with
          # Kramdown and shown only under this platform-owner namespace.
          resources :developer_docs,
                    only: %i[index show],
                    param: :slug,
                    controller: "maintenance/platform/developer_docs",
                    constraints: { slug: /[a-z0-9]+(?:-[a-z0-9]+)*/ }

          # Customer context switching
          resource :customer_context, only: %i[update destroy], controller: "maintenance/platform/customer_contexts"
          get "customer_context/search", to: "maintenance/platform/customer_contexts#search", as: :customer_context_search
        end
      end

      # ====================================================================
      # Modules: Entries & Records (Module category a)
      # ====================================================================
      # For every developed module, surfaces split into 4 areas (AGENTS.md):
      #   a) Entries & Records  -> /:cid/admin/modules/<module>/...           (here)
      #   b) Customer Settings  -> /:cid/admin/settings/modules/<module>/...  (above)
      #   c) Enable/Disable     -> /:cid/admin/maintenance/modules            (above)
      #   d) Platform Settings  -> /:cid/admin/maintenance/platform/module_settings/<module>/...  (above)
      #
      # Public-facing or integration endpoints (webhooks, public checkout,
      # public unsubscribe, send APIs) live outside this rule, in section 1.
      # ====================================================================
      namespace :modules do
        # Authentication
        namespace :authentication do
          resources :users do
            collection { get :trash }
            member { patch :restore }
            resource :activation, only: %i[create destroy], controller: "user_activations"
            resource :mfa_reset,  only: :create,            controller: "user_mfa_resets"
            resources :trusted_devices, only: :destroy, controller: "user_trusted_devices"
            # Create a person-entity entry linked to this user (?entity_id=).
            resources :profiles, only: :create, controller: "user_profiles"
          end
          resources :events, only: :index
        end

        # Email module
        namespace :emails do
          get "dashboard", to: "dashboard#show", as: :dashboard
          resources :health, only: %i[index]
          resources :templates, only: %i[index show new create edit update destroy] do
            resources :versions, only: %i[index show create edit destroy], controller: "template_versions" do
              member { put :default }
            end
            member do
              patch :status
              get :preview
              post :test_send
              post :preview
              post :duplicate
            end
            collection do
              post :test_send
              post :preview
            end
          end
          resources :attachments, only: %i[create show]

          # Send Activity (template → audience list)
          resources :send_activities do
            resource :delivery,     only: :create, controller: "send_activity_deliveries"
            resource :cancellation, only: :create, controller: "send_activity_cancellations"
          end
          resources :lists, controller: "lists" do
            collection { post :preview }
          end

          resources :reports, only: %i[index]
          resources :deliverability, only: %i[index]
          resources :engagement, only: %i[index]
          resources :suppressions, only: %i[index] do
            collection { delete :batch_unblock }
          end
        end

        # SMS
        namespace :sms do
          get "contacts/entity_sync/new", to: "entity_syncs#new", as: :new_contacts_entity_sync
          post "contacts/entity_sync/preview", to: "entity_syncs#preview", as: :preview_contacts_entity_sync
          post "contacts/entity_sync", to: "entity_syncs#create", as: :contacts_entity_sync
          get "contacts/new", to: "contacts#new", as: :new_contact
          get "contacts/:id/edit", to: "contacts#edit", as: :edit_contact
          resources :contacts, except: %i[new edit] do
            resources :consent_events, only: :create
          end
          post "segments/preview", to: "segments#preview", as: :preview_segments
          post "segments/:id/preview", to: "segments#preview", as: :preview_segment
          get "segments/new", to: "segments#new", as: :new_segment
          get "segments/:id/edit", to: "segments#edit", as: :edit_segment
          resources :segments, except: %i[new edit]
          post "campaigns/preview", to: "campaigns#preview", as: :preview_campaigns
          post "campaigns/:id/preview", to: "campaigns#preview", as: :preview_campaign
          post "campaigns/:id/launch", to: "campaign_launches#create", as: :launch_campaign
          post "campaigns/:id/cancel", to: "campaign_cancellations#create", as: :cancel_campaign
          get "campaigns/new", to: "campaigns#new", as: :new_campaign
          get "campaigns/:id/edit", to: "campaigns#edit", as: :edit_campaign
          resources :campaigns, except: %i[new edit] do
            resource :report, only: :show, controller: "campaign_reports"
          end
          resources :messages, only: %i[index show]
          resources :sends, only: :create
          resources :opt_outs, only: :index
        end

        # Payments::Payment — path 'payments' (plural matching module class)
        namespace :payments do
          resources :transactions, only: %i[index show] do
            resources :refunds, only: :create
          end
          resources :reconciliations, only: %i[index show] do
            member { get :download }
          end
          resources :disputes, only: %i[index]
        end

        # Website module — page records and previews; site publication lives in Settings / Website.
        namespace :website do
          get "/", to: "pages#index", as: :root
          resources :pages, except: [:show], controller: "pages" do
            member do
              get :preview
              post :preview
            end
            collection { patch :reorder }
          end
          resources :media, only: :create, controller: "media"
        end

        # AI Assistant cookie composer + STT widget enqueue (admin-only JSON).
        # Customer settings live on the generic module_configs route.
        namespace :ai_assistant do
          resources :transcriptions, only: [:create]
          # Conversation history sidebar. "New chat" is a create here, not a
          # reset of the only thread, so there is no collection delete.
          resources :conversations, only: %i[index create update destroy] do
            member { post :archive }
          end
          resources :messages, only: [:create] do
            member do
              post :undo
              post :discard_proposal
              post :cancel_build
            end
            collection do
              get :mentions
              post :stop
              post :regenerate
            end
          end
        end
      end
    end

    # ========================================================================
    # 2c. MEMBER — /:cid/member/...   (member role required)
    # ========================================================================
    namespace :member do
      resource  :dashboard, only: :show, controller: "dashboards", path: ""
      resource  :profile,   only: %i[show edit update]
      resource  :security,  only: :show, controller: "securities" do
        resource :mfa, only: :destroy, controller: "mfa" do
          get  :setup, on: :collection
          post :setup, on: :collection
        end
      end
      resources :trusted_devices, only: :destroy
      resources :pages, only: :show do
        resources :rows, only: %i[new edit destroy], controller: "page_rows"
      end
      # Starts a launched member journey that begins from one of the member's own records.
      resources :entities, only: [] do
        resources :entries, only: [] do
          post "journeys/:key", to: "entity_entry_journeys#create", as: :journey
        end
      end

      # ---- Payments self-service (member-only) ----
      # IMPORTANT: must come BEFORE resources :surfaces (path: ":key") to
      # prevent the catch-all :key segment swallowing /payments/* paths.
      namespace :payments do
        resources :payment_methods, only: %i[index new create destroy] do
          collection { post :setup_intent }
        end
        resources :subscriptions, only: %i[index show] do
          resource :cancellation, only: :create,
                   controller: "subscription_cancellations"
        end
      end

      resources :surfaces, only: %i[index show], param: :id, path: ":key"
    end
  end

  # Last-resort aliases cannot shadow existing application endpoints. Journey
  # handles glob matching (including nested paths); dots are not format suffixes.
  # Resolver extracts an optional customer prefix from the original PATH_INFO.
  public_shortcut_destinations.each do |controller, action|
    get "/*shortcut_path", to: "#{controller}##{action}", format: false,
        constraints: ->(request) { PageShortcuts::RouteConstraint.matches?(request, controller: controller, action: action) }
  end

  # Public form aliases use the same submission authorization and CSRF
  # callbacks. Website targets never match a POST alias.
  post "/", to: "public_pages#submit", format: false,
       constraints: ->(request) { PageShortcuts::RouteConstraint.matches?(request, controller: "public_pages", action: "submit") }
  post "/*shortcut_path", to: "public_pages#submit", format: false,
       constraints: ->(request) { PageShortcuts::RouteConstraint.matches?(request, controller: "public_pages", action: "submit") }
end
