# frozen_string_literal: true

class ModuleEntriesResolver
  # Application-wide default page size for every admin list. Callers may still
  # override per surface via `per_page:` or the `per_page` query param.
  DEFAULT_PER_PAGE = 10
  # Same ceiling as EntityIndexSetting::PER_PAGE_MAX / member surface settings.
  # CSV export passes a higher `max_per_page:` so a full dump still fits.
  MAX_PER_PAGE = 200

  def self.call(scope:, columns:, params:, filters: [], per_page: nil, max_per_page: MAX_PER_PAGE)
    rel = scope
    rel = apply_search(rel, columns, params[:q]) if params[:q].present?
    rel = apply_filters(rel, filters, params)
    rel = apply_sort(rel, columns, params[:sort], params[:dir])
    paginate(rel, params[:page], params[:per_page] || per_page, max_per_page: max_per_page)
  end

  def self.apply_search(rel, columns, query)
    query = Array.wrap(query).join(" ").strip
    return rel if query.blank?

    searchable = columns.select { |c| c[:searchable] }
    return rel if searchable.empty?

    clauses = searchable.map do |col|
      expr = col[:sql] || "#{rel.table_name}.#{col[:key]}"
      "LOWER(#{expr}) LIKE :q"
    end
    rel.where(clauses.join(" OR "), q: "%#{query.downcase}%")
  end

  def self.apply_filters(rel, filters, params)
    filters.each do |f|
      value = params[f[:key]]
      next if value.blank?

      if f[:scope].respond_to?(:call)
        rel = f[:scope].call(rel, value)
      elsif f[:column]
        rel = rel.where(f[:column] => value)
      end
    end
    rel
  end

  def self.apply_sort(rel, columns, sort_key, dir)
    return rel if sort_key.blank?
    col = columns.find { |c| c[:sortable] && c[:key].to_s == sort_key.to_s }
    return rel unless col

    direction = dir.to_s.downcase == "desc" ? "DESC" : "ASC"
    if col[:sql]
      expr = col[:sql]
      expr = "CAST(#{expr} AS REAL)" if col[:type] == :number
      rel.reorder(Arel.sql("#{expr} #{direction}"))
    else
      rel.reorder(col[:key] => direction.downcase.to_sym)
    end
  end

  # Pagination math is delegated to the pagy gem; this keeps the resolver's
  # `{ rows:, pagination: }` hash contract stable for the 15+ admin call sites.
  def self.paginate(rel, page, per_page, max_per_page: MAX_PER_PAGE)
    requested = per_page.to_s.to_i
    cap = max_per_page.to_s.to_i.positive? ? max_per_page.to_s.to_i : MAX_PER_PAGE
    per_page = requested.positive? ? [requested, cap].min : DEFAULT_PER_PAGE
    pagy = Pagy.new(count: rel.unscope(:select).count, page: [page.to_s.to_i, 1].max, limit: per_page)
    rows = rel.offset(pagy.offset).limit(pagy.limit).to_a
    {
      rows: rows,
      pagination: { page: pagy.page, per_page: pagy.limit, total: pagy.count, total_pages: pagy.pages }
    }
  end

  private_class_method :apply_search, :apply_filters, :apply_sort, :paginate
end
