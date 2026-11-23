# frozen_string_literal: true

module Admin
module Maintenance
module Platform
  # Platform-owner CRUD for time-bounded tenant-admin banners.
  # Path /admin/maintenance/platform/* is already gated to platform_owner?
  # by RouteAuthorization — do not add a duplicate role before_action.
  class AnnouncementsController < ApplicationController
    dashboard_menu_item :maintenance

    # The detail page names the matched tenants. Rendering an unbounded list
    # would print every customer on the platform for a broad segment, so the
    # roster is capped and the total is reported alongside it.
    MATCHING_CUSTOMERS_LIMIT = 50

    # Sample tenants echoed back by the in-form audience preview.
    PREVIEW_SAMPLE_LIMIT = 5

    before_action :set_announcement, only: %i[show edit update destroy]

    helper_method :announcement_presenter

    def index
      result = ModuleEntriesResolver.call(
        scope:   PlatformAnnouncement.kept.newest_first,
        columns: index_columns,
        filters: index_filters,
        params:  index_params
      )
      @columns    = index_columns
      @filters    = index_filters
      @rows       = result[:rows]
      @pagination = result[:pagination]
    end

    def show
      matches              = @announcement.matching_customers
      @matching_count      = @announcement.all_customers? ? nil : matches.count
      @matching_customers  = matches.limit(MATCHING_CUSTOMERS_LIMIT)
      @matching_truncated  = @matching_count.to_i > MATCHING_CUSTOMERS_LIMIT
    end

    def new
      @announcement = PlatformAnnouncement.new
    end

    def edit
    end

    def create
      @announcement = PlatformAnnouncement.new
      save_and_respond(on_failure: :new) do
        redirect_to admin_maintenance_platform_announcements_path(current_customer_id),
                    notice: t("maint_platform.flash.announcements.created")
      end
    end

    def update
      save_and_respond(on_failure: :edit) do
        redirect_to admin_maintenance_platform_announcement_path(current_customer_id, @announcement),
                    notice: t("maint_platform.flash.announcements.updated")
      end
    end

    def destroy
      was_live = @announcement.live?
      previous_users = was_live ? Notifications::Stream.announcement_recipients(@announcement).to_a : []
      @announcement.discard_or_destroy!
      if @announcement.persisted?
        Notifications::Stream.sync_announcement!(@announcement, previous_users: previous_users)
      end
      redirect_to admin_maintenance_platform_announcements_path(current_customer_id),
                  notice: t("maint_platform.flash.announcements.deleted")
    end

    # Answers "who receives this?" while the owner is still editing the
    # segment, so a broadcast is never published blind.
    def audience_preview
      rules = PlatformAnnouncements::TargetRules.parse(params[:target_rules_json])
      if rules.malformed?
        return render json: { error: t("maint_platform.announcements.form.errors.target_rules_invalid") },
                      status: :unprocessable_entity
      end

      matches = rules.matching_customers
      render json: {
        count: matches.count,
        sample: matches.limit(PREVIEW_SAMPLE_LIMIT).map { |c| { id: c.id, name: c.name } }
      }
    end

    private

    def announcement_presenter(announcement)
      AnnouncementPresenter.new(announcement)
    end

    def set_announcement
      @announcement = PlatformAnnouncement.kept.find(params[:id])
    end

    def announcement_params
      params.require(:platform_announcement).permit(
        :title, :body_en, :body_zh, :severity, :link_url, :status, :audience,
        :starts_at, :ends_at, :target_rules_json
      )
    end

    def save_and_respond(on_failure:)
      result = PlatformAnnouncements::Activities::Save.call(record: @announcement, params: announcement_params)
      return yield if result.success?

      apply_save_errors(result)
      render on_failure, status: :unprocessable_entity
    end

    # Keeps the contract's per-attribute mapping so the form can highlight the
    # offending field instead of dumping everything onto :base.
    def apply_save_errors(result)
      result.errors.each do |attribute, messages|
        Array(messages).each { |message| @announcement.errors.add(attribute, message) }
      end
    end

    def index_params
      params.permit(:q, :sort, :dir, :page, :status, :severity).to_h.symbolize_keys
    end

    def index_columns
      @index_columns ||= [
        { key: :title, label: column_label(:title), sortable: true, searchable: true },
        { key: :severity, label: column_label(:severity), type: :badge, sortable: true,
          badge: ->(row) { announcement_presenter(row).severity_badge },
          cell:  ->(row) { announcement_presenter(row).severity_badge[:label] } },
        { key: :status, label: column_label(:status), type: :badge, sortable: true,
          badge: ->(row) { announcement_presenter(row).status_badge },
          cell:  ->(row) { announcement_presenter(row).status_badge[:label] } },
        { key: :audience, label: column_label(:audience), sortable: false, searchable: false,
          cell: ->(row) { announcement_presenter(row).audience_label } },
        { key: :starts_at, label: column_label(:starts_at), type: :datetime, sortable: true, searchable: false },
        { key: :ends_at, label: column_label(:ends_at), type: :datetime, sortable: true, searchable: false },
        { key: :updated_at, label: column_label(:updated_at), type: :datetime, sortable: true, searchable: false }
      ]
    end

    def index_filters
      @index_filters ||= [
        { key: :status, label: t("maint_platform.announcements.index.filters.status"), column: :status,
          options: PlatformAnnouncement::STATUSES.map { |s| [ t("common.status.#{s}"), s ] } },
        { key: :severity, label: t("maint_platform.announcements.index.filters.severity"), column: :severity,
          options: PlatformAnnouncement::SEVERITIES.map { |s|
            [ t("maint_platform.announcements.severities.#{s}"), s ]
          } }
      ]
    end

    def column_label(key)
      t("maint_platform.announcements.index.columns.#{key}")
    end
  end
end
end
end
