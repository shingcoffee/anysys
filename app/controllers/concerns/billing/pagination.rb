# frozen_string_literal: true

module Billing
  module Pagination
    extend ActiveSupport::Concern

    private

    def billing_filters(statuses: [], platform: false, search: true)
      @filters = {}
      q = search ? scalar_filter(:q) : nil
      @filters[:q] = q.strip if q.present?
      status = scalar_filter(:status)
      if status.present?
        statuses.include?(status) ? @filters[:status] = status : invalid_billing_filter
      end
      if platform
        tenant_id = scalar_filter(:tenant_id)
        if tenant_id.present?
          tenant_id.match?(/\A\d{8}\z/) ? @filters[:tenant_id] = tenant_id : invalid_billing_filter
        end
      end
      @filters
    end

    def filter_billing_invoices(relation, platform: false, search: true)
      billing_filters(statuses: ::Billing::Invoice::STATUSES, platform: platform, search: search)
      relation = relation.where(status: @filters[:status]) if @filters[:status]
      relation = relation.where(customer_id: @filters[:tenant_id]) if @filters[:tenant_id]
      if @filters[:q]
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@filters[:q].downcase)}%"
        relation = relation.where("LOWER(billing_invoices.number) LIKE ? ESCAPE '\\'", pattern)
      end
      relation
    end

    def paginate_billing(relation)
      page = scalar_filter(:page)
      invalid_billing_filter if page.present? && !page.match?(/\A[1-9]\d*\z/)
      page = page.to_s.match?(/\A[1-9]\d*\z/) ? page.to_i : 1
      @pagy = Pagy.new(count: relation.count, page: page, limit: 25, overflow: :last_page)
      @pagination = {
        page: @pagy.page, per_page: @pagy.limit, total: @pagy.count, total_pages: @pagy.pages
      }
      @page_path = lambda do |number|
        options = request.path_parameters.except(:format).merge(@filters || {})
        locale = scalar_filter(:locale)
        options[:locale] = locale if I18n.available_locales.map(&:to_s).include?(locale)
        url_for(options.merge(page: number, only_path: true))
      end
      relation.offset(@pagy.offset).limit(@pagy.limit).to_a
    end

    def recent_billing(relation)
      table = relation.klass.arel_table
      relation.reorder(table[:created_at].desc, table[:id].desc)
    end

    def scalar_filter(key)
      value = params[key]
      return value if value.is_a?(String)
      invalid_billing_filter unless value.nil?
      nil
    end

    def invalid_billing_filter
      flash.now[:alert] = t("admin_settings.flash.billing.invalid_filters")
    end
  end
end
