# frozen_string_literal: true

module Admin
  class EntityEntriesController < ApplicationController
    include PageRendering

    before_action :find_entity
    before_action :find_entry, only: %i[show edit destroy]

    # A submission from the "+ Add New" dialog lands here in its frame
    # (PageEntityEntryReturn): the saved entry goes back to the dropdown. A
    # link row was saved from a record page's dialog, whose opener reloads
    # that page, so the notice waits for the reload.
    def show
      if quick_add_frame?
        return render(:quick_add_created, layout: false) unless @entity.category_bridge?

        flash.keep(:notice)
        return render(:link_saved, layout: false)
      end

      @display = ::Entities::EntryDisplay.new(entity: @entity, entries: [@entry], customer_id: current_customer.id,
                                              audience: EntityAttributeAudience::ADMIN)
      @associations = ::Entities::EntryAssociations.new(entity: @entity, customer: current_customer).sections(@entry)
      if @entity.active? && !@entity.category_bridge?
        @journey_starts = ::Journeys::RecordStarts.new(entity: @entity, customer_id: current_customer.id, entry: @entry)
      end
      @reveal_section = flash[:reveal_section]&.dig("id")
    end

    # Entries are created and edited through the entity's launched page: the
    # form posts to the page's submit endpoint, which saves the record and
    # returns here (PageEntityEntryReturn). When a live journey opens that
    # page with a user step, the admin creates the account first.
    def new
      journey = user_start_journey
      return redirect_to(new_admin_modules_authentication_user_path(current_customer.id, journey: journey.key), status: :see_other) if journey

      prepare_entry_page_render(:create)

      respond_to do |format|
        format.html do
          if quick_add_frame?
            render :quick_add, layout: false
          else
            render :new, layout: "dashboard"
          end
        end
      end
    end

    def edit
      prepare_entry_page_render(:update)

      respond_to do |format|
        format.html do
          if entry_page_frame?
            render :quick_add, layout: false
          else
            render :edit, layout: "dashboard"
          end
        end
      end
    end

    def destroy
      delete_entries!(entry_scope.where(id: @entry.id))

      respond_to do |format|
        format.html do
          redirect_to entries_return_path, notice: t("common.flash.entry_deleted")
        end
        format.json { head :no_content }
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
      deletion_failure(e.record&.errors&.full_messages&.to_sentence.presence || e.message)
    rescue ActiveRecord::InvalidForeignKey
      deletion_failure
    end

    def batch_destroy
      raw = params[:ids]
      ids = Array(raw)
      unless (raw.nil? || raw.is_a?(Array)) && ids.all? { |id| (id.is_a?(String) || id.is_a?(Integer)) && id.to_s.match?(/\A[1-9]\d*\z/) }
        return deletion_failure(t("routes_audit.invalid_selection"))
      end

      count = delete_entries!(entry_scope.where(id: ids.uniq))
      respond_to do |format|
        format.html { redirect_to entries_return_path, notice: t("common.flash.entries_deleted", count: count) }
        format.json { render json: { success: true, count: count } }
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
      deletion_failure(e.record&.errors&.full_messages&.to_sentence.presence || e.message)
    rescue ActiveRecord::InvalidForeignKey
      deletion_failure
    end

    private

    # A bridge entity has no entry form of its own: only a page opened by id
    # (a journey step, or a record page's link dialog) renders for it.
    def prepare_entry_page_render(action)
      requested = requested_entry_page(action)
      raise ActiveRecord::RecordNotFound if @entity.category_bridge? && requested.nil?

      @page = requested || ::Pages::EntryPageResolver.page_for(entity: @entity, audience: EntityAttributeAudience::ADMIN, action: action)
      return unless @page

      prepare_page_render(
        @page,
        submit_params: { return_to: ENTITY_ENTRY_RETURN, entry_id: @entry&.id, label_field: quick_add_label_field,
                         page: requested&.id }.compact,
        quick_add_depth: entry_page_frame? ? quick_add_depth + 1 : 0,
        prefill: entry_page_prefill,
        presentation: :entry,
        form: entry_page_form_options
      )
    end

    # Not inside a run or the "+ Add New" dialog, which create the record alone.
    def user_start_journey
      return if quick_add_frame? || page_run || !@entity.person?

      page = requested_entry_page(:create) ||
             ::Pages::EntryPageResolver.page_for(entity: @entity, audience: EntityAttributeAudience::ADMIN, action: :create)
      page && ::Journeys::UserStart.for_page(page: page, customer_id: current_customer.id)
    end

    # The launched admin page `?page=` names, when it is bound to this entity
    # and serves the action.
    def requested_entry_page(action)
      return unless params[:page].is_a?(String) && params[:page].match?(/\A[1-9]\d*\z/)

      page = Page.accessible.launched.for_audience(EntityAttributeAudience::ADMIN).for_entity(@entity.id).find_by(id: params[:page])
      page if page&.serves?(action)
    end

    def entry_page_prefill
      if @entry
        ::Pages::EntryPrefill.values(page: @page, entry: @entry, audience: page_runtime_audience)
      else
        ::Pages::Prefill.values(page: @page, params: params, audience: page_runtime_audience, viewer: page_runtime_user)
      end
    end

    # A new entry's page loads into the "+ Add New" dialog frame, and so does
    # a link row's edit page, opened from a record page's dialog.
    def entry_page_frame? = quick_add_frame? && (@entry.nil? || @entity.category_bridge?)

    # In a dialog frame the page submits into that frame and Cancel closes it.
    def entry_page_form_options
      return { frame: true, update: @entry.present? } if entry_page_frame?

      { cancel_path: admin_entity_path(current_customer.id, @entity), update: @entry.present? }
    end

    # The "+ Add New" dialog loads new into its frame, and the submission
    # returns to that frame; nested dialogs name their level in the frame id.
    def quick_add_depth
      Admin::Entities::QuickAddDialogComponent.depth_of(turbo_frame_request_id)
    end
    helper_method :quick_add_depth

    def quick_add_frame? = !quick_add_depth.nil?

    # Dropdown option label slug, echoed through the quick-add form.
    def quick_add_label_field
      params[:label_field] if params[:label_field].is_a?(String)
    end
    helper_method :quick_add_label_field

    # The label the dropdown would show for this entry: the display field when
    # it can label a reference for admins, numbered when another record already
    # shows the same text, and "Untitled (#id)" otherwise.
    def quick_add_label(entry)
      source = ::Entities::ReferenceOptions.new(entity_id: @entity.id, label_field: quick_add_label_field,
                                                customer_id: current_customer_id, audience: EntityAttributeAudience::ADMIN)
      return ::Entities::ReferenceLabels.text(nil, entry.id) unless source.usable?

      raw = entry.data_json[quick_add_label_field]
      label = ::Entities::ReferenceLabels.text(raw, entry.id)
      source.label_taken?(raw, except_id: entry.id) ? ::Entities::ReferenceLabels.numbered(label, entry.id) : label
    end
    helper_method :quick_add_label

    def entry_scope
      EntityEntry.where(customer_id: current_customer.id, entity_id: @entity.id)
    end

    def delete_entries!(scope)
      EntityEntry.transaction do
        entries = scope.order(:id).lock.to_a
        entries.each do |entry|
          result = ::Entities::DeleteEntry.call(entry: entry)
          raise ActiveRecord::RecordNotDestroyed.new(result.errors.to_sentence, result.entry) unless result.success?
        end
        entries.size
      end
    end

    def entries_return_path
      admin_entity_path(current_customer.id, @entity)
    end

    def deletion_failure(message = nil)
      message = message.presence || t("routes_audit.entry_deletion_failed")
      respond_to do |format|
        format.html { redirect_to entries_return_path, alert: message }
        format.json { render json: { success: false, errors: [message] }, status: :unprocessable_entity }
      end
    end

    def find_entity
      scope = Entity.where(customer_id: current_customer.id).or(Entity.shared)
      scope = scope.active if action_name.in?(%w[new edit])
      @entity = scope.find(request.path_parameters[:entity_id])
    end

    def find_entry
      @entry = entry_scope.find(request.path_parameters[:id])
    end
  end
end
