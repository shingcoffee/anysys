# frozen_string_literal: true

module Member
  # The rows a member manages from their own record (a cart's items), through
  # the page that manages them (Pages::MemberRows): Add and Change open that
  # page on a fresh run locking the record in, and Remove deletes a row.
  # Member-only, and every action re-checks the page, the record and the row.
  class PageRowsController < BaseController
    before_action :load_page

    def new
      raise ActiveRecord::RecordNotFound unless @page.serves?(:create)

      open_page(found!(::Pages::MemberRows.record(page: @page, record_id: params[:record], viewer: current_user,
                                                  customer_id: current_customer.id)))
    end

    def edit
      raise ActiveRecord::RecordNotFound unless @page.serves?(:update)

      row = managed_row!
      open_page(record_of(row), entry: row)
    end

    def destroy
      row = managed_row!
      record = record_of(row)
      result = ::Entities::DeleteEntry.call(entry: row)
      flash_key = result.success? ? :notice : :alert
      message = result.success? ? t("member.record_rows.removed") : result.errors.to_sentence
      redirect_to record_path(record), flash_key => message, status: :see_other
    end

    private

    def load_page
      @page = Page.accessible.launched.find(params[:page_id])
      raise ActiveRecord::RecordNotFound unless ::Pages::MemberRows.managing?(@page)
    end

    def managed_row!
      found!(::Pages::MemberRows.row(page: @page, entry_id: params[:id], viewer: current_user, customer_id: current_customer.id))
    end

    def record_of(row)
      found!(::Pages::MemberRows.record_of(page: @page, row: row, viewer: current_user, customer_id: current_customer.id))
    end

    def found!(record) = record || raise(ActiveRecord::RecordNotFound)

    def open_page(record, entry: nil)
      _run, token = JourneyRun.pin!(customer_id: current_customer.id, user: current_user, session: session, page: @page,
                                    inputs: { @page.page_inputs.first["field"] => record.id.to_s })
      path = member_page_path(current_customer.id, @page, entry: entry&.id)
      redirect_to ::Pages::RunLink.append(path, token, page: nil), status: :see_other
    end

    def record_path(record) = member_surface_path(current_customer.id, "entity_#{record.entity_id}", record.id)
  end
end
