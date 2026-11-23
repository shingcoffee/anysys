# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
    # UsersController
    #
    # Admin interface for managing tenant users.
    # Restricted to users with admin or owner roles.
    #
    # URL Pattern: /:customer_id/modules/authentication/users/...
    #
    # New/create also run a journey's user step (`journey` names it): the
    # account gets a random password, and the journey continues on the page
    # whose new person record is linked to it (Journeys::UserStart).
    #
    class UsersController < ApplicationController
      include ::Authentication::OwnerAccountProtectable
      include PageAudienceRouting

      dashboard_menu_item :modules

      before_action :find_user, only: %i[show edit update destroy restore]
      before_action :protect_owner_account!, only: %i[update destroy restore]
      before_action :find_journey_start, only: %i[new create]

      # GET /:customer_id/authentication/admin/users
      def index
        @columns = user_index_columns
        @filters = user_index_filters
        @table_params = params.permit(:q, :sort, :dir, :page, :role, :status).to_h.symbolize_keys
        @filters.each do |filter|
          next if filter[:default].blank? || @table_params[filter[:key]].present?

          @table_params[filter[:key]] = filter[:default]
        end
        scope = ::Authentication::User.where(customer_id: current_customer_id).where.not(status: :trashed).includes(:roles)
        result = ModuleEntriesResolver.call(scope: scope, columns: @columns, filters: @filters, params: @table_params)
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      # GET /:customer_id/admin/modules/authentication/users/trash
      def trash
        @columns = user_index_columns
        @table_params = params.permit(:q, :sort, :dir, :page).to_h.symbolize_keys
        scope = ::Authentication::User.where(customer_id: current_customer_id, status: :trashed).includes(:roles)
        result = ModuleEntriesResolver.call(scope: scope, columns: @columns, params: @table_params)
        @rows       = result[:rows]
        @pagination = result[:pagination]
      end

      # DELETE /:customer_id/admin/modules/authentication/users/:id
      def destroy
        if @user == current_user
          redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                      alert: t("admin_modules.flash.users.trash_self_blocked")
          return
        end

        if @user.move_to_trash
          redirect_to admin_modules_authentication_users_path(current_customer_id),
                      notice: t("admin_modules.flash.users.trashed", name: @user.display_name)
        else
          redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                      alert: @user.errors.full_messages.to_sentence
        end
      end

      # PATCH /:customer_id/admin/modules/authentication/users/:id/restore
      def restore
        if @user.restore_from_trash
          redirect_to admin_modules_authentication_user_path(current_customer_id, @user),
                      notice: t("admin_modules.flash.users.restored", name: @user.display_name)
        else
          redirect_to trash_admin_modules_authentication_users_path(current_customer_id),
                      alert: @user.errors.full_messages.to_sentence
        end
      end

      # GET /:customer_id/authentication/admin/users/:id
      def show
        @trusted_devices = @user.trusted_devices.active.order(last_used_at: :desc)
        @profile_sections = ::Authentication::UserDomainProfiles.call(
          user: @user, customer: current_customer, viewer: current_user
        )
      end

      # GET /:customer_id/authentication/admin/users/new
      def new
        @user = ::Authentication::User.new(customer_id: current_customer_id)
      end

      # POST /:customer_id/authentication/admin/users
      def create
        @user = ::Authentication::User.new(user_create_params)
        @user.customer_id = current_customer_id
        @user.password = @user.password_confirmation = Devise.friendly_token(24) if @journey_start

        role_key = params.dig(:authentication_user, :role).presence || "member"
        unless role_assignable?(@user, role_key)
          @user.errors.add(:base, I18n.t("admin_modules.flash.users.invalid_role"))
          return render :new, status: :unprocessable_entity
        end

        # Member quota is not an accepted TOCTOU: two creates that both see
        # usage < limit would both persist. Re-check under the customer row lock.
        guard = nil
        saved = false
        current_customer.with_lock do
          guard = ::Billing::Quota::Guard.check(customer: current_customer, item_key: "member")
          if guard.allowed?
            @user.skip_confirmation!
            saved = persist_with_role(role_key) { @user.save && issue_journey_run }
          end
        end
        unless guard.allowed?
          @user.errors.add(:base, guard.message)
          flash.now[:alert] = guard.message
          return render :new, status: :unprocessable_entity
        end

        if saved
          notice = t("admin_modules.flash.users.created", name: @user.display_name)
          return redirect_to(journey_continue_path, notice: notice) if @journey_start

          redirect_to admin_modules_authentication_users_path(current_customer_id), notice: notice
        else
          render :new, status: :unprocessable_entity
        end
      end

      # GET /:customer_id/authentication/admin/users/:id/edit
      def edit
      end

      # PATCH/PUT /:customer_id/authentication/admin/users/:id
      def update
        update_params = params.dig(:authentication_user, :password).present? ? user_update_params : user_update_params.except(:password, :password_confirmation)
        role_key = params.dig(:authentication_user, :role)

        if role_key.present? && !role_assignable?(@user, role_key)
          @user.errors.add(:base, I18n.t("admin_modules.flash.users.invalid_role"))
          @user.assign_attributes(update_params)
          return render :edit, status: :unprocessable_entity
        end

        if self_sensitive_update?(update_params) && !self_password_confirmed?
          @user.assign_attributes(update_params)
          @user.errors.add(:current_password, I18n.t("admin_modules.flash.users.current_password_invalid"))
          return render :edit, status: :unprocessable_entity
        end

        if persist_with_role(role_key) { @user.update(update_params) }
          redirect_to admin_modules_authentication_user_path(current_customer_id, @user), notice: t("admin_modules.flash.users.updated", name: @user.display_name)
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      # ID and name both open the user. First and last name stay searchable
      # without their own columns, and a hidden id column lets search match the
      # numeric id while the visible id column keeps numeric sort order.
      # Sign-in counts, IPs, and lock time stay on the detail page.
      def user_index_columns
        [
          { key: :id, label: I18n.t("admin_misc.entities.columns.id"), sortable: true, searchable: false,
            mono: true, nowrap: true, width: "w-24", link: true },
          { key: :id, sortable: false, searchable: true, display: false, sql: "CAST(users.id AS TEXT)" },
          { key: :full_name, label: I18n.t("common.labels.name"), sortable: true, searchable: false,
            width: "min-w-40", sql: "users.last_name || ' ' || users.first_name", link: true },
          { key: :first_name, sortable: true, searchable: true, display: false },
          { key: :last_name, sortable: true, searchable: true, display: false },
          { key: :email, label: I18n.t("common.labels.email"), sortable: true, searchable: true,
            mono: true, break: true, width: "min-w-48" },
          { key: :primary_role_key, label: I18n.t("common.labels.role"), type: :badge, sortable: false, searchable: false,
            badge: ->(user) { { variant: { "owner" => :purple, "admin" => :primary }[user.primary_role_key] || :default, label: user.role_display_name } },
            cell: ->(user) { user.role_display_name } },
          { key: :status, label: I18n.t("common.labels.status"), type: :badge, sortable: true, searchable: false,
            badge: ->(user) { { variant: user.active? ? :success : :danger, label: I18n.t("common.status.#{user.status}") } },
            cell: ->(user) { I18n.t("common.status.#{user.status}") } },
          { key: :mfa_state, label: I18n.t("common.labels.mfa"), type: :badge, sortable: false, searchable: false,
            badge: ->(user) {
              if user.otp_required_for_login? then { variant: :success, label: I18n.t("common.status.enabled") }
              elsif user.mfa_configured?      then { variant: :warning, label: I18n.t("common.status.configured") }
              else                                  { variant: :default, label: I18n.t("common.status.off") }
              end
            },
            cell: ->(user) { user.mfa_configured? ? I18n.t("common.status.configured") : I18n.t("common.status.off") } },
          { key: :last_sign_in_at, label: I18n.t("common.labels.last_sign_in"), type: :datetime, relative: true,
            sortable: true, searchable: false, nowrap: true },
          { key: :created_at, label: I18n.t("common.labels.created_at"), type: :datetime,
            sortable: true, searchable: false, nowrap: true, mobile: true }
        ]
      end

      def user_index_filters
        [
          { key: :role, label: I18n.t("common.labels.role"),
            default: "member", include_blank: false,
            options: [
              [I18n.t("admin_modules.users.index.all_roles"), "all"],
              [I18n.t("common.roles.owner"), "owner"],
              [I18n.t("common.roles.admin"), "admin"],
              [I18n.t("common.roles.member"), "member"]
            ],
            scope: lambda { |rel, value|
              if value.to_s == "all"
                rel
              else
                rel.where(id: ::UsersRole.joins(:role).where(roles: { key: value.to_s, system: true }).select(:user_id))
              end
            } },
          { key: :status, label: I18n.t("common.labels.status"),
            options: ::Authentication::User.statuses.except("trashed").keys.map { |status| [I18n.t("common.status.#{status}"), status] },
            column: :status }
        ]
      end

      def find_user
        @user = ::Authentication::User.where(customer_id: current_customer_id).find(params[:id])
      end

      def find_journey_start
        return if params[:journey].blank?

        @journey_start = ::Journeys::UserStart.find(key: params[:journey], customer_id: current_customer_id, viewer: current_user)
        return if @journey_start

        redirect_to new_admin_modules_authentication_user_path(current_customer_id), alert: t("journeys.runtime.unavailable")
      end

      # Runs inside the user's transaction so a run that cannot be issued
      # never leaves an account behind whose random password nobody knows.
      def issue_journey_run
        @journey_token = ::Journeys::UserStart.begin!(start: @journey_start, account: @user, viewer: current_user, session: session) if @journey_start
        true
      end

      def journey_continue_path
        run_surface_path(@journey_start.page, @journey_token, audience: EntityAttributeAudience::ADMIN)
      end

      def user_create_params
        params.require(:authentication_user).permit(:first_name, :last_name, :email, :password, :password_confirmation)
      end

      def user_update_params
        params.require(:authentication_user).permit(:first_name, :last_name, :email, :password, :password_confirmation)
      end

      def self_sensitive_update?(update_params)
        return false unless @user.id == current_user.id

        email_changing = update_params[:email].present? &&
          update_params[:email].to_s.downcase != @user.email.to_s.downcase
        password_changing = params.dig(:authentication_user, :password).present?
        email_changing || password_changing
      end

      def self_password_confirmed?
        return false unless current_user.password_set?

        ::Authentication::PasswordVerification.authenticate(
          user: current_user,
          password: params.dig(:authentication_user, :current_password).to_s
        ).present?
      end

      def role_assignable?(user, role_key)
        return true if role_key.blank?
        return false if role_key.to_s == "owner" && !user.eligible_for_owner_role?
        return true if user.owner? && !current_user&.owner?

        resolve_system_role(user, role_key).present?
      end

      def persist_with_role(role_key)
        ok = false
        ::Authentication::User.transaction(requires_new: true) do
          raise ActiveRecord::Rollback unless yield
          raise ActiveRecord::Rollback unless assign_user_role(@user, role_key)

          ok = true
        end
        ok
      end

      def assign_user_role(user, role_key)
        return true if role_key.blank?

        role_record = resolve_system_role(user, role_key)
        unless role_record
          user.errors.add(:base, I18n.t("admin_modules.flash.users.invalid_role"))
          return false
        end

        user.with_lock do
          # This surface replaces only the reserved role. Preserve existing
          # supplemental roles, and let Assign replace the reserved join in
          # place while enforcing the fixed owner and single-role invariants.
          role_ids = user.roles.reject { |role| UserRoles::AssignmentPolicy.reserved?(role) }.map(&:id)
          result = UserRoles::Operation::Assign.call(
            user: user, role_ids: role_ids + [role_record.id], actor: current_user, request: request
          )
          next true if result.success?

          result.errors.each do |attribute, messages|
            Array(messages).each { |message| user.errors.add(attribute, message) }
          end
          false
        end
      end

      def resolve_system_role(user, role_key)
        if role_key.to_s == "member"
          user.customer.roles.find_or_create_by!(key: "member") do |r|
            r.name          = I18n.t("common.roles.member")
            r.system        = true
            r.locked_grants = true
          end
        else
          user.customer.roles.system.find_by(key: role_key.to_s)
        end
      end
    end
    end
  end
end
