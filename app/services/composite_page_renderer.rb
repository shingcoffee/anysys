# frozen_string_literal: true

class CompositePageRenderer
  WIDTH_CLASSES = {
    "full" => "col-span-12",
    "half" => "col-span-12 md:col-span-6",
    "third" => "col-span-12 md:col-span-4",
    "two_thirds" => "col-span-12 md:col-span-8"
  }.freeze

  def initialize(modules_config, customer_id:, params: {}, audience: EntityAttributeAudience.for_user(Current.user, customer_id: customer_id),
                 viewer: Current.user)
    @modules_config = modules_config || []
    @customer_id = customer_id
    @params = params
    @audience = audience
    @viewer = viewer
  end

  def render_modules
    @modules_config.map { |mod_config| build_module_data(mod_config) }
  end

  private

  def build_module_data(mod_config)
    entity = resolve_entity(mod_config["entity_id"])
    config = mod_config["config"] || {}

    base = {
      id: mod_config["id"],
      module_type: mod_config["module_type"] || "form",
      title: mod_config["title"],
      entity: entity,
      width: mod_config["width"] || "full",
      width_class: WIDTH_CLASSES[mod_config["width"]] || WIDTH_CLASSES["full"],
      visibility: mod_config["visibility"],
      events: mod_config["events"] || {},
      config: config
    }

    if base[:module_type] == "list"
      list_data = fetch_list_data(entity, config)
      base.merge!(
        records: list_data[:records],
        pagination: list_data[:pagination],
        columns: resolve_columns(entity, config["columns"]),
        row_action_paths: row_action_paths(list_data[:records], config)
      )
    end

    base
  end

  def resolve_entity(entity_id)
    return nil unless entity_id && @customer_id
    Entity.find_by(id: entity_id, customer_id: [@customer_id, nil])
  end

  def fetch_list_data(entity, config)
    return { records: [], pagination: { total_count: 0 } } unless entity

    builder = FlowchartRuntime::QueryBuilder.for_entity(
      entity,
      customer_id: @customer_id,
      scope: People::Ownership.scope(entity, viewer: @viewer, audience: @audience, customer_id: @customer_id)
    )

    conditions = config["conditions"]
    builder = builder.where(conditions, {}) if conditions.present?

    sort_field = (@params[:sort].presence || config["defaultSort"].presence || "created_at").to_s
    allowed = visible_schema(entity).map { |field| field["name_slug"] }
    sort_field = "created_at" unless allowed.include?(sort_field.delete_prefix("data."))
    sort_dir = (@params[:direction].presence || config["defaultDirection"].presence || "desc").to_s
    sort_ref = sort_field.start_with?("data.") ? sort_field : "data.#{sort_field}"
    builder = builder.order(sort_ref, sort_dir)

    page_size = (config["pageSize"] || 25).to_s.to_i
    page_num = (@params[:page] || 1).to_s.to_i
    builder = builder.paginate(page: page_num, per_page: page_size)

    result = begin
      builder.execute
    rescue FlowchartRuntime::JsonPathValidator::Error, FlowchartRuntime::QueryBuilder::Error
      builder.order("data.created_at", "desc").execute
    end
    {
      records: result.records,
      pagination: {
        total_count: result.total_count,
        page: result.page,
        per_page: result.per_page,
        total_pages: result.total_pages,
        has_next: result.has_next
      }
    }
  end

  # Built only from the tile's own config; stored record data never becomes an href.
  def row_action_paths(records, config)
    action = config["row_action"]
    return {} unless action.is_a?(Hash)

    action_key = (action["action_key"] || action[:action_key]).to_s
    field = (action["field"] || action[:field]).to_s
    return {} unless field.match?(Pages::FormParams::SLUG)

    records.each_with_object({}) do |record, paths|
      path = Pages::ActionLink.path(customer_id: @customer_id, action_key: action_key, prefill: { field => record.id })
      paths[record.id] = path if path
    end
  end

  def resolve_columns(entity, column_slugs)
    return [] unless entity && column_slugs
    schema = visible_schema(entity)
    Array(column_slugs).filter_map do |slug|
      field = schema.find { |f| f["name_slug"] == slug }
      next unless field
      { slug: slug, name: field["name"], html_type: field["html_type"] || "text" }
    end
  end

  def visible_schema(entity)
    Array(entity.property_schema_json).select { |field| EntityAttributeAudience.visible_to?(field, @audience) }
  end
end
