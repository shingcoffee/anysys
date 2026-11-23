# frozen_string_literal: true

module Admin
  module Modules
    module Authentication
      # User detail page laid out like the entity entry page: domain profile
      # sections in the main column, beside a sticky sidebar with an account
      # details card (sign-ins and trusted devices folded inside it) and a
      # section index.
      class UserShowComponent < ApplicationComponent
        include EntityAttributeGroupingHelper

        ROLE_COLORS = { "owner" => "violet", "admin" => "indigo" }.freeze
        SIGN_INS_COLOR = "sky"
        # Header actions share a row on phones, like the entry page's.
        ACTION_CLASSES = "min-h-11 flex-1 whitespace-nowrap sm:min-h-9 sm:flex-none"
        DANGER_ACTION_CLASSES = "#{ACTION_CLASSES} text-danger hover:text-danger".freeze
        # Folded sidebar cards keep the entry page's plain card header.
        SIDEBAR_SUMMARY_CLASSES = "flex cursor-pointer list-none items-center gap-3 px-4 py-3.5 transition-base " \
                                  "hover:bg-surface-hover focus-visible:outline-2 focus-visible:-outline-offset-2 " \
                                  "focus-visible:outline-accent sm:px-5 [&::-webkit-details-marker]:hidden"

        attr_reader :user, :trusted_devices, :viewer, :customer_id, :profile_sections

        def initialize(user:, trusted_devices:, viewer:, customer_id:, profile_sections:)
          @user = user
          @trusted_devices = Array(trusted_devices)
          @viewer = viewer
          @customer_id = customer_id
          @profile_sections = profile_sections
        end

        def header_actions
          return [] if protected_owner?
          return [restore_action] if user.trashed?

          [edit_action, reset_mfa_action, activation_action, trash_action].compact
        end

        def role_variant
          { "owner" => :purple, "admin" => :primary }.fetch(user.primary_role_key, :default)
        end

        def viewing_self?
          user == viewer
        end

        def cid = customer_id
        def id_prefix = "user-#{user.id}"
        def section_id(key) = "#{id_prefix}-#{key}"

        def status_badge
          { label: t("common.status.#{user.status}"), variant: user.active? ? :success : :danger }
        end

        def mfa_badge
          if user.otp_required_for_login?
            { label: t("common.status.enabled"), variant: :success }
          elsif user.mfa_configured?
            { label: t("admin_modules.users.show.mfa_configured"), variant: :warning }
          else
            { label: t("admin_modules.users.show.mfa_not_set_up"), variant: :default }
          end
        end

        def identity_icon_path = attribute_group_icon_path("user")
        def identity_icon_class = soft_tile(ROLE_COLORS.fetch(user.primary_role_key, "slate"))

        def profiles_icon_path = EntitiesContributor::ICONS[:domain]

        def devices_meta = t("admin_modules.users.show.trusted_devices_count", count: trusted_devices.size)

        def render_chevron
          tag.svg(class: "size-4 shrink-0 text-text-muted transition-transform duration-200 group-open/section:rotate-180",
                  fill: "none", viewBox: "0 0 24 24", stroke: "currentColor", "stroke-width": 2, "aria-hidden": true) do
            tag.path(d: "m6 9 6 6 6-6", "stroke-linecap": "round", "stroke-linejoin": "round")
          end
        end

        # Label / value rows like the entry page's Record details card; a
        # +badge+ variant renders the value as a badge.
        def detail_rows
          [
            { label: t("admin_misc.entities.columns.id"), value: "##{user.id}" },
            { label: t("admin_modules.users.show.role"), value: user.role_display_name, badge: role_variant },
            { label: t("common.labels.status"), value: status_badge[:label], badge: status_badge[:variant] },
            { label: t("admin_modules.users.show.mfa"), value: mfa_badge[:label], badge: mfa_badge[:variant] },
            { label: t("common.labels.created_at"), value: timestamp(user.created_at) },
            { label: t("common.labels.updated_at"), value: timestamp(user.updated_at) }
          ]
        end

        # Blank times carry their own muted dash from #timestamp; blank
        # addresses mute the value cell.
        def sign_in_rows
          [
            { label: t("admin_modules.users.show.current_sign_in"), value: timestamp(user.current_sign_in_at), numeric: true },
            { label: t("admin_modules.users.show.current_sign_in_ip"), value: user.current_sign_in_ip.presence || t("common.labels.em_dash"),
              muted: user.current_sign_in_ip.blank? },
            { label: t("admin_modules.users.show.last_sign_in"), value: timestamp(user.last_sign_in_at), numeric: true },
            { label: t("admin_modules.users.show.last_sign_in_ip"), value: user.last_sign_in_ip.presence || t("common.labels.em_dash"),
              muted: user.last_sign_in_ip.blank? },
            { label: t("admin_modules.users.show.sign_in_count"), value: user.sign_in_count, numeric: true },
            { label: t("admin_modules.users.show.failed_attempts"), value: user.failed_attempts, numeric: true,
              note: (device_time_label("admin_modules.users.show.locked_at", user.locked_at) if user.locked_at.present?) }
          ]
        end

        # The dialog the profiles' association Add buttons open.
        def association_dialog?
          profile_sections.any? do |section|
            section.profiles.any? { |profile| profile.associations_writable && profile.associations.any? }
          end
        end

        def index_items
          profiles = profile_sections.map do |section|
            {
              id: UserDomainSectionComponent.section_id(section, id_prefix: id_prefix),
              label: UserDomainSectionComponent.title(section),
              dot: UserDomainSectionComponent.dot_class(section)
            }
          end
          profiles = [{ id: section_id("profiles"), label: t("admin_modules.users.show.profiles.heading") }] if profiles.empty?

          [
            *profiles,
            { id: section_id("sign-ins"), label: t("admin_modules.users.show.sign_in_and_devices"),
              dot: attribute_group_color_classes(SIGN_INS_COLOR), count: trusted_devices.size }
          ]
        end

        def timestamp(value)
          return tag.span(t("common.labels.em_dash"), class: "text-text-tertiary") if value.blank?

          tag.time(helpers.format_datetime(value), datetime: value.iso8601)
        end

        def device_time_label(key, value, date_only: false)
          return tag.span(t(key, time: t("common.labels.em_dash")), class: "text-text-tertiary") if value.blank?

          date = date_only ? value.to_date : value
          tag.time(t(key, time: l(date, format: :long)), datetime: date.iso8601)
        end

        private

        def soft_tile(color) = "ring-1 ring-inset #{attribute_group_color_classes(color, variant: :soft)}"

        def protected_owner?
          user.owner? && !viewer&.owner?
        end

        def edit_action
          {
            label: t("common.actions.edit"),
            path: helpers.edit_admin_modules_authentication_user_path(cid, user),
            variant: :primary,
            icon: :edit,
            class: ACTION_CLASSES
          }
        end

        def reset_mfa_action
          return if viewing_self? || !user.mfa_configured?

          {
            label: t("admin_modules.users.actions.reset_mfa"),
            path: helpers.admin_modules_authentication_user_mfa_reset_path(cid, user),
            variant: :secondary,
            class: ACTION_CLASSES,
            data: {
              turbo_method: :post,
              turbo_confirm: t("admin_modules.users.show.reset_mfa_confirm", name: user.display_name)
            }
          }
        end

        def trash_action
          return if viewing_self?

          {
            label: t("admin_modules.users.actions.move_to_trash"),
            path: helpers.admin_modules_authentication_user_path(cid, user),
            variant: :secondary,
            icon: :trash,
            class: DANGER_ACTION_CLASSES,
            data: {
              turbo_method: :delete,
              turbo_confirm: t("admin_modules.users.show.trash_confirm", name: user.display_name)
            }
          }
        end

        def restore_action
          {
            label: t("admin_modules.users.actions.restore"),
            path: helpers.restore_admin_modules_authentication_user_path(cid, user),
            variant: :primary,
            class: ACTION_CLASSES,
            data: {
              turbo_method: :patch,
              turbo_confirm: t("admin_modules.users.show.restore_confirm", name: user.display_name)
            }
          }
        end

        def activation_action
          return if viewing_self?

          if user.active?
            {
              label: t("admin_modules.users.actions.deactivate"),
              path: helpers.admin_modules_authentication_user_activation_path(cid, user),
              variant: :secondary,
              class: DANGER_ACTION_CLASSES,
              data: {
                turbo_method: :delete,
                turbo_confirm: t("admin_modules.users.show.deactivate_confirm", name: user.display_name)
              }
            }
          else
            {
              label: t("admin_modules.users.actions.activate"),
              path: helpers.admin_modules_authentication_user_activation_path(cid, user),
              variant: :secondary,
              class: ACTION_CLASSES,
              data: { turbo_method: :post }
            }
          end
        end
      end
    end
  end
end
