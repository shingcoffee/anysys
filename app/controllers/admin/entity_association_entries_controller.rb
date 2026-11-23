# frozen_string_literal: true

module Admin
  # Bridge rows of one primary entry for one of its entity's associations,
  # managed from the entry detail page: add one or many, edit, delete.
  # Add and Edit normally open in the entry page's quick-add dialog (a Turbo
  # frame request); the full dashboard pages remain for direct visits.
  # When a launched page saves these rows (Entities::AssociationPages), Add
  # and Edit hand over to it with the entry pinned into its locked input, so
  # the save runs the page's flowchart; these forms are the fallback.
  class EntityAssociationEntriesController < ApplicationController
    include SafeReturnTo

    before_action :find_context
    before_action :find_row, only: %i[edit update destroy]
    helper_method :association_return_path, :association_row_path

    def new
      return open_link_page(:create) if link_page(:create)

      @template_form = blank_form
      @forms = [blank_form]

      respond_to do |format|
        format.html { render_form(:new) }
      end
    end

    def create
      respond_to do |format|
        format.html do
          signal, ctx = ::Entities::Activities::CreateAssociationEntries.call(
            customer: current_customer, actor: current_user, entity: @entity, entry: @entry,
            association_id: @association.id, rows: rows_params
          )

          case signal.to_h[:semantic]
          when :success
            saved(t("admin_misc.entities.association_entries.created", count: ctx[:models].size))
          when :forbidden
            raise CanCan::AccessDenied, t("common.flash.access_denied")
          else
            @template_form = blank_form
            @forms = ctx[:forms]
            @errors = ctx[:errors]
            render_form(:new, status: :unprocessable_entity)
          end
        end
      end
    end

    def edit
      return open_link_page(:update, @row) if link_page(:update)

      @entry_form = ::Entities::EntryForm.new(entity: @association.bridge, customer: current_customer, entry: @row,
                                              links: @association.links(@entry))

      respond_to do |format|
        format.html { render_form(:edit) }
      end
    end

    def update
      data = entry_data_params

      respond_to do |format|
        format.html do
          signal, ctx = ::Entities::Activities::UpdateAssociationEntry.call(
            customer: current_customer, actor: current_user, entity: @entity, entry: @entry,
            association_id: @association.id, row: @row, params: data
          )

          case signal.to_h[:semantic]
          when :success
            saved(t("admin_misc.entities.association_entries.updated"))
          when :forbidden
            raise CanCan::AccessDenied, t("common.flash.access_denied")
          else
            @entry_form = ctx[:form]
            render_form(:edit, status: :unprocessable_entity)
          end
        end
      end
    end

    def destroy
      result = ::Entities::DeleteEntry.call(entry: @row)

      if result.success?
        redirect_to section_path, notice: t("admin_misc.entities.association_entries.deleted"), status: :see_other
      else
        redirect_to section_path, alert: result.errors.to_sentence.presence || t("routes_audit.entry_deletion_failed"),
                                  status: :see_other
      end
    end

    private

    def link_page(mode)
      @link_pages ||= {}
      return @link_pages[mode] if @link_pages.key?(mode)

      @link_pages[mode] = ::Entities::AssociationPages.find(association: @association, entity: @entity,
                                                            customer_id: current_customer.id, mode: mode)
    end

    # The dialog frame (or the window) follows to the link entity's entry form
    # for that page, on a fresh run that locks the entry in.
    def open_link_page(mode, row = nil)
      page = link_page(mode)
      _run, token = JourneyRun.pin!(customer_id: current_customer.id, user: current_user, session: session, page: page,
                                    inputs: { @association.source_slug => @entry.id.to_s })
      bridge = @association.bridge
      path = row ? edit_admin_entity_entry_path(current_customer.id, bridge, row) : new_admin_entity_entry_path(current_customer.id, bridge)
      redirect_to ::Pages::RunLink.append(path, token, page: page), status: :see_other
    end

    # The quick-add dialog level whose frame requested this, or nil.
    def dialog_depth
      Admin::Entities::QuickAddDialogComponent.depth_of(turbo_frame_request_id)
    end
    helper_method :dialog_depth

    def render_form(action, status: :ok)
      if dialog_depth
        render "#{action}_dialog", status: status, layout: false
      else
        render action, status: status, layout: "dashboard"
      end
    end

    # In the dialog the notice waits for the entry page reload the dialog's
    # opener performs once it sees the saved marker.
    def saved(notice)
      if dialog_depth
        flash[:notice] = notice
        @notice = notice
        render :saved_dialog, layout: false
      else
        redirect_to section_path, notice: notice, status: :see_other
      end
    end

    def find_context
      @entity = Entity.where(customer_id: current_customer.id).or(Entity.shared).active.non_bridge
                      .find(request.path_parameters[:entity_id])
      @entry = EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id)
                          .find(request.path_parameters[:entry_id])
      @associations = ::Entities::EntryAssociations.new(entity: @entity, customer: current_customer)
      @association = @associations.find(request.path_parameters[:association_id])
      raise ActiveRecord::RecordNotFound unless @association
    end

    def find_row
      @row = @associations.rows(@association, @entry).find(request.path_parameters[:id])
    end

    def blank_form
      ::Entities::EntryForm.new(entity: @association.bridge, customer: current_customer, links: @association.links(@entry))
    end

    # The user page passes return_to so Edit and Delete come back to the
    # course section there. Anything else returns to the entry detail section.
    def section_path
      association_return_path
    end

    def association_return_path
      safe_return_to || admin_entity_entry_path(current_customer.id, @entity, @entry,
                                                anchor: Admin::Entities::AssociationSectionComponent.section_id(@association))
    end

    def association_row_path(row)
      extra = {}
      extra[:return_to] = safe_return_to if safe_return_to
      admin_entity_entry_association_entry_path(current_customer.id, @entity, @entry, @association.id, row, **extra)
    end

    # Submitted rows in the order the form listed them; malformed rows reach
    # EntryForm, which reports their shape.
    def rows_params
      rows = params[:rows]
      raise ActionController::BadRequest unless parameter_object?(rows)

      rows.keys.sort_by { |key| key.to_s.to_i }.map { |key| rows[key] }
    end

    def entry_data_params
      entry = params[:entry]
      data = entry[:data] if parameter_object?(entry)
      raise ActionController::BadRequest unless parameter_object?(data)

      data
    end

    def parameter_object?(value)
      value.is_a?(ActionController::Parameters) || value.is_a?(Hash)
    end
  end
end
