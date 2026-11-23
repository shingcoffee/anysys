# frozen_string_literal: true

module Admin
  # A single form's publishing slide-over and the batch launch actions. The
  # forms lists are the Forms tabs of domains (Domains::PagesController) and
  # entities (Entities::PagesController).
  class PagesController < ApplicationController
    dashboard_menu_item :entities

    # Publishing slide-over for a single page (turbo-frame `page-publishing`).
    def show
      @page = Page.accessible.find(params[:id])
      @return_to = admin_page_path(current_customer.id, @page)
      @close_path = Admin::Pages::BrowsePath.for(@page, customer_id: current_customer.id)
    end

    def batch_update
      action = params[:action_key].to_s
      unless %w[activate deactivate launch take_offline].include?(action)
        return batch_failure(t("routes_audit.pages.invalid_action"))
      end

      raw_ids = params[:ids]
      unless raw_ids.nil? || raw_ids.is_a?(Array)
        return batch_failure(t("routes_audit.invalid_selection"))
      end
      ids = Array(raw_ids)
      unless ids.all? { |id| (id.is_a?(String) || id.is_a?(Integer)) && id.to_s.match?(/\A[1-9]\d*\z/) }
        return batch_failure(t("routes_audit.invalid_selection"))
      end

      scope = action == "activate" ? Page.with_deleted : Page.all
      count = Page.transaction do
        pages = scope.where(customer_id: current_customer.id, id: ids.uniq).order(:id).lock.to_a
        pages.each do |page|
          case action
          when "activate"
            page.update!(status: :active)
            page.launch! if page.launched?
          when "deactivate" then page.update!(status: :inactive)
          when "launch" then page.launch!
          when "take_offline" then page.take_offline!
          end
        end
        pages.size
      end

      respond_to do |format|
        format.html { redirect_to admin_domains_path(current_customer.id), notice: t("common.flash.pages_updated", count: count) }
        format.json { render json: { success: true, count: count } }
      end
    rescue ActiveRecord::RecordInvalid => e
      batch_failure(e.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotUnique
      batch_failure(t("routes_audit.pages.update_failed"))
    end

    private

    def batch_failure(message)
      respond_to do |format|
        format.html { redirect_to admin_domains_path(current_customer.id), alert: message }
        format.json { render json: { success: false, error: message }, status: :unprocessable_entity }
      end
    end
  end
end
