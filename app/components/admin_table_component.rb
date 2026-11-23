# frozen_string_literal: true

# AdminTableComponent
#
# Single, consistent list view used by every admin sub-item index page.
# Pairs with `Listable` + `ModuleEntriesResolver` to drive search, sort,
# filters, and pagination through query params (`q`, `sort`, `dir`, `page`).
class AdminTableComponent < ApplicationComponent
  TYPES = %i[text badge datetime date number association truncate boolean].freeze

  # Optional leading-icon tile for the primary column. Callers opt in per row
  # with a column option `leading: ->(row) { { icon: :document, tone: :accent } }`.
  # Kept as a stroked-path registry (not raw SVG from callers) so no markup
  # crosses the controller boundary.
  LEADING_ICONS = {
    document: "M9 13h6m-6 4h6m2 4H7a2 2 0 01-2-2V5a2 2 0 012-2h7l5 5v11a2 2 0 01-2 2z",
    code:     "M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4",
    mail:     "M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z",
    building: "M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21"
  }.freeze

  LEADING_TONES = {
    accent:  "bg-accent-subtle text-accent-text",
    purple:  "bg-purple-100 text-purple-700",
    info:    "bg-info-subtle text-info",
    default: "bg-surface-active text-text-muted"
  }.freeze

  # Only these column types get `tabular-nums` — applying a numeric font
  # variant to prose columns renders text with fixed-width digits/glyphs.
  NUMERIC_TYPES = %i[number datetime date].freeze

  attr_reader :rows, :columns, :pagination, :params,
              :search, :filters, :row_path, :row_path_data, :row_actions, :row_menu_actions,
              :empty_state, :frame_id, :base_path

  def initialize(rows:, columns:, pagination:, params:,
                 search: nil, filters: [], row_path: nil, row_path_data: nil,
                 row_actions: nil, row_menu_actions: nil, empty_state: nil,
                 frame_id: "admin-table", base_path: nil)
    @rows              = Array(rows)
    @columns           = columns.map { |c| normalize_column(c) }
    @pagination        = pagination || {}
    @params            = symbolize_params(params)
    @search            = search
    @filters           = Array(filters)
    @row_path          = row_path
    @row_path_data     = (row_path_data || {}).symbolize_keys
    @row_actions       = row_actions
    @row_menu_actions  = row_menu_actions
    @empty_state       = empty_state
    @frame_id          = frame_id
    @base_path         = base_path.to_s
  end

  # Data attributes for the primary-column row link. Defaults to escaping the
  # table turbo-frame; callers can target another frame (e.g. a slide-over).
  def row_link_data
    { turbo_frame: "_top" }.merge(row_path_data)
  end

  def has_search?  = !search.nil?
  def has_filters? = filters.any?
  def has_row_actions? = !row_actions.nil? || !row_menu_actions.nil?
  def has_inline_row_actions? = !row_actions.nil?
  def has_row_menu? = !row_menu_actions.nil?

  def sort_link_for(column)
    return nil unless column[:sortable]

    sort_param = params[:sort].to_s
    active     = sort_param == column[:key].to_s
    next_dir   = (active && params[:dir] == "asc") ? "desc" : "asc"
    arrow      = if active
                   params[:dir] == "desc" ? "↓" : "↑"
    end

    href = "#{base_path}?#{params.merge(sort: column[:key], dir: next_dir).to_query}"
    { href: href, arrow: arrow, active: active }
  end

  def page_link(page_num)
    "#{base_path}?#{params.merge(page: page_num).to_query}"
  end

  def cell_value(row, column)
    if column[:cell].respond_to?(:call)
      column[:cell].call(row)
    else
      row.public_send(column[:key])
    end
  end

  def cell_text(row, column)
    value = cell_value(row, column)
    case column[:type]
    when :datetime
      format_datetime(value)
    when :date
      format_date(value)
    when :truncate
      helpers.truncate(value.to_s, length: column[:truncate] || 60)
    when :boolean
      value ? I18n.t("common.labels.yes") : I18n.t("common.labels.no")
    else
      value.to_s
    end
  end

  # Single badge hash for callers that expect one value. Prefer `badges_for`
  # when rendering — columns may return one hash or an Array of hashes.
  def badge_for(row, column)
    badges_for(row, column).first
  end

  # Normalizes a column's `badge:` lambda to an Array of
  # `{ variant:, label: }` hashes. Returns [] when the column is not a badge
  # column or the lambda returns blank.
  def badges_for(row, column)
    return [] unless column[:type] == :badge && column[:badge].respond_to?(:call)

    result = column[:badge].call(row)
    return [] if result.blank?

    Array.wrap(result).map { |b| b.is_a?(Hash) ? b.symbolize_keys : nil }.compact
  end

  def numeric_class(column)
    NUMERIC_TYPES.include?(column[:type]) ? "tabular-nums" : ""
  end

  # Optional per-column text treatment. `mono:` is for identifiers such as
  # ids and hostnames; `nowrap:` keeps short tokens on one line; `break:`
  # lets a long hostname wrap inside the cell.
  def text_cell_classes(column)
    [
      ("font-mono text-[13px] tabular-nums tracking-tight text-text-primary" if column[:mono]),
      ("whitespace-nowrap" if column[:nowrap]),
      ("break-all" if column[:break])
    ].compact.join(" ")
  end

  def plain_cell(row, column)
    text = cell_text(row, column)
    classes = text_cell_classes(column)
    return text if classes.blank?

    tag.span(text, class: classes)
  end

  # Renders date/datetime cells as a <time> element so the exact timestamp is
  # always available on hover even when the visible text is relative. Returns
  # nil for non-temporal columns and for values that cannot be formatted (nil,
  # strings), which fall back to the plain `cell_text` path.
  def datetime_cell(row, column)
    return nil unless NUMERIC_TYPES.include?(column[:type]) && column[:type] != :number

    value = cell_value(row, column)
    return nil unless value.respond_to?(:strftime)

    exact = column[:type] == :date ? format_date(value) : format_datetime(value)
    {
      text:  column[:relative] ? relative_time(value) : exact,
      exact: exact,
      iso:   (value.iso8601 if value.respond_to?(:iso8601))
    }
  end

  # "2 days ago" / "in 3 days". Leans on Rails' already-translated
  # distance-of-time strings and only supplies the surrounding phrasing.
  def relative_time(value)
    distance = helpers.time_ago_in_words(value)
    future   = value.to_time > Time.current
    I18n.t("chrome.admin_table.#{future ? 'time_in' : 'time_ago'}", time: distance)
  end

  def total_count = pagination[:total].to_i

  def showing_from
    per  = (pagination[:per_page].presence || rows.size).to_i
    page = (pagination[:page].presence || 1).to_i
    ((page - 1) * per) + 1
  end

  def showing_to = showing_from + rows.size - 1

  # Always-on result summary: a range while paginated, a plain total otherwise.
  # Returns nil when the caller did not supply a total, so tables that opt out
  # of counting simply render no summary.
  def count_summary
    return nil unless total_count.positive?

    if (pagination[:total_pages] || 1).to_i > 1
      I18n.t("chrome.admin_table.showing_range", from: showing_from, to: showing_to, total: total_count)
    else
      I18n.t("chrome.admin_table.result_count", count: total_count)
    end
  end

  def has_toolbar? = has_search? || has_filters? || count_summary.present?

  # One chip per active filter, each linking to the same view with that filter
  # dropped. `page` is reset so removing a filter cannot land on a page that no
  # longer exists.
  def active_filter_chips
    filters.filter_map do |f|
      next unless filter_engaged?(f)

      value = params[f[:key]].to_s
      option = Array(f[:options]).find { |(_label, val)| val.to_s == value }
      {
        label:       f[:label],
        value_label: option ? option.first : value,
        remove_path: "#{base_path}?#{params.except(f[:key], :page).to_query}"
      }
    end
  end

  def clear_filters_path
    "#{base_path}?#{params.except(*filters.map { |f| f[:key] }, :page).to_query}"
  end

  def alignment_class(column)
    case column[:align]
    when :right  then "text-right"
    when :center then "text-center"
    else              "text-left"
    end
  end

  def width_class(column)
    column[:width].to_s
  end

  def empty_after_search?
    rows.empty? && (active_search? || active_filters?)
  end

  def active_search?
    !search.nil? && params[search[:param]].to_s.present?
  end

  def active_filters?
    filters.any? { |filter| filter_engaged?(filter) }
  end

  # A filter value equal to `default:` is the resting state of the control.
  # It still narrows the query, but it is not an applied chip and it does not
  # replace the table's own empty state.
  def filter_engaged?(filter)
    value = params[filter[:key]].to_s
    return false if value.blank?
    return false if filter[:default].present? && value == filter[:default].to_s

    true
  end

  # `row_path` links the first visible column. Set `link: true` on the columns
  # that should open the row; once any visible column opts in, only those link.
  def row_link?(column, index)
    return false if row_path.nil?

    if linked_columns?
      column[:link] == true
    else
      index.zero?
    end
  end

  def linked_columns?
    return @linked_columns if defined?(@linked_columns)

    @linked_columns = visible_columns.any? { |column| column[:link] }
  end

  def menu_actions_for(row)
    return [] unless has_row_menu?

    Array(row_menu_actions.call(row))
  end

  # Build link_to keyword args for a row action. Non-GET methods become Turbo
  # data attributes (`data: { turbo_method: ... }`) so they actually issue the
  # right verb under turbo-rails — `link_to method:` alone is ignored.
  def link_args_for(action)
    method = (action[:method] || :get).to_sym
    data   = (action[:data] || {}).dup
    if method != :get
      data[:turbo_method] ||= method
    end
    # Row actions navigate or mutate — they should never be swapped into the
    # table's turbo-frame. Default to escaping unless the caller asked to stay
    # in a specific frame.
    data[:turbo_frame] ||= "_top"
    args = { data: data }
    args[:target] = action[:target] if action[:target]
    args[:rel] = action[:rel] if action[:rel]
    args
  end

  # Tailwind text-color class for a row action. DELETE actions (or anything
  # explicitly tagged `tone: :danger`) render in red; everything else is muted.
  def action_tone_class(action)
    danger = action[:tone] == :danger || (action[:method] || :get).to_sym == :delete
    danger ? "text-danger hover:text-danger" : "text-text-secondary hover:text-text-primary"
  end

  def visible_columns
    columns.reject { |col| col[:display] == false }
  end

  def subtitle_for(row, column)
    return nil unless column[:subtitle].respond_to?(:call)

    column[:subtitle].call(row).presence
  end

  # Resolves a column's `leading:` lambda into an icon path + tone classes for
  # the primary-cell tile. Returns nil when the column opts out or the icon key
  # is unknown, so the cell falls back to the plain name/subtitle stack.
  def leading_for(row, column)
    return nil unless column[:leading].respond_to?(:call)

    spec = column[:leading].call(row)
    return nil if spec.blank?

    path = LEADING_ICONS[spec[:icon].to_sym] if spec[:icon]
    return nil if path.nil?

    { path: path, tone: LEADING_TONES.fetch((spec[:tone] || :default).to_sym, LEADING_TONES[:default]) }
  end

  private

  def normalize_column(col)
    type      = col[:type] || :text
    sortable  = col.key?(:sortable)   ? col[:sortable]   : true
    searchable = col.key?(:searchable) ? col[:searchable] : (type == :text)
    col.merge(type: type, sortable: sortable, searchable: searchable)
  end

  def symbolize_params(p)
    if p.respond_to?(:to_unsafe_h)
      p.to_unsafe_h.symbolize_keys
    else
      (p || {}).symbolize_keys
    end
  end

  def format_datetime(value)
    return I18n.t("common.labels.em_dash") if value.blank?
    value.respond_to?(:strftime) ? I18n.l(value, format: :long) : value.to_s
  end

  def format_date(value)
    return I18n.t("common.labels.em_dash") if value.blank?
    value.respond_to?(:strftime) ? I18n.l(value.to_date, format: :long) : value.to_s
  end
end
