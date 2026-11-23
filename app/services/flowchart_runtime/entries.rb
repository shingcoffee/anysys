# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

module FlowchartRuntime
  # Tenant- and entity-scoped access to entity entries for generated activities.
  # Entity attributes live in the JSON `data` column, so attribute predicates
  # bind json_extract with literal values (never ctx-path resolution) and writes
  # go through the accessors EntityEntry.build_for defines.
  module Entries
    class Error < StandardError; end
    class UnknownAttribute < Error; end

    INTERNAL_COLUMNS = %w[id customer_id entity_id entity_version_number user_id data created_at updated_at].freeze
    UPSERT_LOCK_TTL = 10
    ADJUST_LOCK_TTL = 10
    ADJUST_LOCK_WAIT = 1.0

    module_function

    def scope(ctx)
      entity = ctx[:bound_entity]
      return EntityEntry.none unless entity

      EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)
    end

    def scope_for(ctx, entity)
      raise Error, "entity is required" unless entity
      unless EntityResolver.accessible?(entity.id, customer_id: ctx[:customer_id])
        raise Error, "entity is not accessible"
      end

      EntityEntry.build_for(entity).where(customer_id: ctx[:customer_id], entity_id: entity.id)
    end

    # Bound entity when +entity+ is blank, otherwise a tenant-reachable entity
    # looked up by name or id. +record_scope+ "own" keeps only the signed-in
    # member's rows (People::Ownership); "all" keeps every tenant row.
    def scoped(ctx, entity: nil, record_scope: "all")
      if entity.blank?
        target = ctx && ctx[:bound_entity]
        relation = scope(ctx)
      else
        target = resolve_entity!(ctx, entity)
        return EntityEntry.none unless target

        relation = scope_for(ctx, target)
      end
      return relation unless record_scope.to_s == "own"
      return relation.none unless target

      apply_own_scope(relation, ctx, target)
    end

    def find_by(ctx_or_scope, conditions, lock = false)
      rel = where(ctx_or_scope, conditions)
      rel = rel.lock if lock
      rel.first
    end

    # Trusted person row for the run. Reads only ctx[:current_person_ids]
    # ({ "<person entity id>" => entry_id }); never params. Returns the entry
    # when it still exists in the run tenant and belongs to the bound entity.
    def find_current_person(ctx, entity_id: nil, lock: false)
      entity = ctx && ctx[:bound_entity]
      return unless entity&.person?

      map = ctx[:current_person_ids]
      return unless map.is_a?(Hash)

      entry_id = map[(entity_id.presence || entity.id).to_s]
      return if entry_id.blank?

      rel = scope(ctx)
      rel = rel.lock if lock
      rel.find_by(id: entry_id)
    end

    def where(ctx_or_scope, conditions)
      relation = relation_for(ctx_or_scope)
      conditions.to_h.reduce(relation) do |rel, (key, value)|
        slug = key.to_s
        if slug == "id"
          rel.where(id: value)
        else
          raise UnknownAttribute, slug unless known_slug?(rel, slug)

          safe = JsonPathValidator.safe_json_path!(slug)
          rel.where("json_extract(entity_entries.data, '$.#{safe}') = ?", value)
        end
      end
    end

    def assign(entry, attributes, strict: false, write_mode: "overwrite", skip_nil: false)
      writable = writable_slugs(entry.class)
      references = reference_slugs(entry.class)
      attributes.to_h.each do |key, value|
        slug = key.to_s
        if INTERNAL_COLUMNS.include?(slug) || !writable.include?(slug)
          raise UnknownAttribute, slug if strict

          next
        end
        value = reference_value(value) if references.include?(slug)
        next if skip_nil && value.nil?
        next if write_mode.to_s == "only_blank" && !empty_value?(entry.public_send(slug))

        entry.public_send("#{slug}=", value)
      end
      entry
    end

    # A File or Image field reads as its attachment, empty when it holds no file.
    def empty_value?(value)
      return !value.attached? if value.is_a?(ActiveStorage::Attached)

      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    def reference_slugs(model_class)
      entity = model_class.respond_to?(:bound_entity) ? model_class.bound_entity : nil
      Array(entity&.property_schema_json).filter_map { |row| row["name_slug"].to_s if reference_target_id(row) }
    end

    # References are stored as record id strings, which is what lookups and
    # roll-ups match on; a step may assign the record or its numeric id.
    def reference_value(value)
      case value
      when Array then value.map { |item| reference_value(item) }
      when EntityEntry then value.id.to_s
      when Integer then value.to_s
      else value
      end
    end

    # Saves through Entries::Save as the run's audience (system when no person
    # submitted it); errors land in ctx. The first save of the page's new
    # record also writes the page's bridge rows. Pass a Reform form to sync it
    # onto its model before persist; pass an EntityEntry that was already
    # assigned in place.
    def save(ctx, entry_or_form)
      form = entry_or_form.is_a?(::Reform::Form) ? entry_or_form : nil
      entry = form ? form.model : entry_or_form
      assert_writable!(ctx, entry)
      bridged = bridge_rows_pending?(ctx, entry)
      contract = form || ::Entries::Save::Written.new(model: entry)
      result = ::Entries::Save.call(contract: contract,
                                    audience: ctx[:audience].presence || ::Entities::Lifecycle::SYSTEM)
      return record_failure(ctx, result.errors, result.field_errors) unless result.ok?
      return true unless bridged && result.entry

      save_bridge_rows(ctx, result.entry)
    end

    # The record the reference field +slug+ on +record+ points at, in the
    # run's tenant; nil when the field is blank or that record is gone.
    def referenced(ctx, record, slug)
      raise Error, "record is required" unless record.is_a?(EntityEntry)

      target = reference_target(record.entity, slug)
      raise Error, "#{slug} is not a reference field" unless target

      id = Array(record.respond_to?(slug) ? record.public_send(slug) : record.data_json[slug.to_s]).first
      scope_for(ctx, target).find_by(id: id.to_s) if id.present?
    end

    def reference_target(entity, slug)
      attribute = Array(entity.try(:property_schema_json)).find { |row| row.is_a?(Hash) && row["name_slug"].to_s == slug.to_s }
      target_id = reference_target_id(attribute)
      Entity.find_by(id: target_id) if target_id
    end

    # A reference is stored either as an EntityReference (bridge participants)
    # or as a choice list filled from another entity's records.
    def reference_target_id(attribute)
      return unless attribute.is_a?(Hash)
      return attribute["entity_id"].presence if attribute["type"] == Entity::ENTITY_REFERENCE_TYPE

      attribute.dig("config", "entity_id").presence if ::Entities::ReferenceLabels.reference?(attribute)
    end

    # Adds +amount+ to (or, with +subtract+, takes it from) the number field
    # +slug+ on +entry+ and saves it, reloading the stored row under a lock so
    # two submits cannot both spend the same stock. A result past +minimum+ or
    # +maximum+ writes nothing and fails the run with +message+ (default: how
    # much is left); returns the new value or false.
    def adjust(ctx, entry, slug, amount:, subtract: false, minimum: nil, maximum: nil, message: nil, field: nil)
      assert_writable!(ctx, entry)
      slug = slug.to_s
      raise UnknownAttribute, slug unless writable_slugs(entry.class).include?(slug)

      change = number(amount)
      raise Error, "#{amount.inspect} is not a number" unless change

      apply = lambda do
        current = number(entry.public_send(slug)) || 0
        result = tidy_number(subtract ? current - change : current + change)
        floor = number(minimum)
        ceiling = number(maximum)
        return refuse_adjustment(ctx, :below_minimum, tidy_number(current - floor), message, field) if floor && result < floor
        return refuse_adjustment(ctx, :above_maximum, tidy_number(ceiling - current), message, field) if ceiling && result > ceiling

        assign(entry, { slug => result }, strict: true)
        save(ctx, entry) && result
      end

      return apply.call unless entry.persisted?

      with_adjust_lock(ctx, entry, field) do
        entry.reload
        apply.call
      end
    end

    def number(value)
      return value if value.is_a?(Numeric)

      text = value.to_s.strip
      return if text.empty?

      Integer(text, 10)
    rescue ArgumentError
      Float(text, exception: false)
    end

    def tidy_number(value)
      value.is_a?(Float) ? value.round(10) : value
    end

    def with_adjust_lock(ctx, entry, field)
      lock_name = CacheKey.scoped(ctx[:customer_id], "adjust", entry.id)
      token = SecureRandom.hex(16)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + ADJUST_LOCK_WAIT
      begin
        loop do
          break if Lock.acquire(ctx[:customer_id], lock_name, token, ttl: ADJUST_LOCK_TTL)
          return Step.fail(ctx, :"adjust_number.busy", field: field) if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.02
        end
        yield
      rescue Lock::Error, CacheKey::Error
        Step.fail(ctx, :"adjust_number.busy", field: field)
      ensure
        release_lock(ctx[:customer_id], lock_name, token)
      end
    end

    def refuse_adjustment(ctx, code, available, message, field)
      available = [available, 0].max
      if LocalizedText.resolve(message, locale: :en).present?
        return Step.fail_message(ctx, message, code: :"adjust_number.#{code}", field: field, variables: { "available" => available })
      end

      if code == :below_minimum
        Step.fail(ctx, :"adjust_number.below_minimum", field: field, available: available)
      else
        Step.fail(ctx, :"adjust_number.above_maximum", field: field, available: available)
      end
    end

    def upsert(ctx, match:, attributes:, on_match: "update")
      entity = ctx[:bound_entity]
      raise Error, "entity is required" unless entity

      digest = Digest::SHA256.hexdigest(JSON.generate(canonicalize(match)))
      lock_name = CacheKey.scoped(ctx[:customer_id], "upsert", entity.id, digest)
      token = SecureRandom.hex(16)
      acquired = Lock.acquire(ctx[:customer_id], lock_name, token, ttl: UPSERT_LOCK_TTL)
      return Step.fail(ctx, :record_busy) unless acquired

      begin
        entry = find_by(ctx, match)
        created = entry.nil?
        if entry
          case on_match.to_s
          when "skip" then return [entry, false]
          when "fail" then return Step.fail(ctx, :record_already_exists)
          end
        else
          entry = scope(ctx).new(customer_id: ctx[:customer_id], entity_id: entity.id)
        end
        assign(entry, match.to_h.merge(attributes.to_h))
        return false unless save(ctx, entry)

        [entry, created]
      ensure
        release_lock(ctx[:customer_id], lock_name, token)
      end
    end

    def destroy(ctx, entry)
      assert_writable!(ctx, entry)
      return true if entry.destroy

      Step.fail(ctx, :record_not_destroyed)
    end

    def archive(ctx, entry, field:, by_field: nil)
      attrs = { field => Time.current }
      attrs[by_field] = ctx[:current_user_id] if by_field
      assign(entry, attrs, strict: true)
      save(ctx, entry)
    end

    def where_attributes(relation, conditions, _ctx = nil)
      conditions.to_h.reduce(relation) do |rel, (key, value)|
        slug = key.to_s
        if slug == "id"
          rel.where(id: value)
        else
          safe = JsonPathValidator.safe_json_path!(slug)
          rel.where("json_extract(entity_entries.data, '$.#{safe}') = ?", value)
        end
      end
    end

    QueryResult = Struct.new(:records, :pagination, keyword_init: true)
    AGGREGATE_METHODS = {
      "sum" => :sum, "avg" => :average, "average" => :average,
      "min" => :minimum, "minimum" => :minimum,
      "max" => :maximum, "maximum" => :maximum,
      "count" => :count
    }.freeze

    def filter(ctx, conditions = nil, entity: nil, record_scope: "all")
      apply_conditions(scoped(ctx, entity: entity, record_scope: record_scope), conditions, ctx)
    end

    def apply_conditions(relation, conditions, ctx)
      return relation if blank_conditions?(conditions)

      if conditions.is_a?(Hash) && !conditions.key?("type") && !conditions.key?("rules") && !conditions.key?("conditions")
        return where(relation, conditions)
      end

      rules = to_where_rules(conditions)
      return relation if rules.nil?

      WhereClauseBuilder.apply(relation, rules, ctx)
    end

    def query(ctx, conditions: nil, select: [], returns: "records", order_by: nil,
              order_direction: "asc", then_order_by: nil, then_order_direction: "asc",
              distinct: false, limit: nil, page: nil, per_page: nil, offset: nil,
              entity: nil, record_scope: "all")
      rel = filter(ctx, conditions, entity: entity, record_scope: record_scope)
      rel = apply_order(rel, order_by, order_direction)
      rel = apply_order(rel, then_order_by, then_order_direction)
      rel = rel.distinct if distinct
      total = per_page ? rel.except(:select, :order).count : nil
      rel = apply_limit(rel, limit, page, per_page, offset)
      slugs = Array(select).map(&:to_s).reject(&:empty?)

      records =
        if returns.to_s == "values"
          pluck_attributes(rel, slugs)
        elsif slugs.any?
          rel.to_a.map { |entry| slugs.to_h { |slug| [slug, read_attr(entry, slug)] } }
        else
          rel.to_a
        end

      QueryResult.new(records: records, pagination: pagination_hash(total, page, per_page))
    end

    def tally(ctx, conditions: nil, result_as: "count", distinct: false, distinct_field: nil, group_by: nil,
              entity: nil, record_scope: "all")
      rel = filter(ctx, conditions, entity: entity, record_scope: record_scope)
      case result_as.to_s
      when "exists" then rel.exists?
      when "absent" then !rel.exists?
      else
        rel = apply_group(rel, group_by)
        if distinct && distinct_field.to_s.present?
          rel.distinct.count(count_expression(distinct_field))
        elsif distinct
          rel.distinct.count
        else
          rel.count
        end
      end
    end

    def aggregate(ctx, round_to: nil, **query)
      round_numeric(compute_aggregate(ctx, **query), round_to)
    end

    def compute_aggregate(ctx, conditions: nil, function: nil, field: nil, aggregations: {},
                          group_by: nil, group_by_fields: [], having: nil, result_format: "scalar",
                          entity: nil, record_scope: "all")
      target = resolve_entity!(ctx, entity)
      raise Error, "entity is required" unless target

      row_scope = scoped(ctx, entity: entity, record_scope: record_scope)
      builder = QueryBuilder.for_entity(target, customer_id: ctx[:customer_id], scope: row_scope)
      rules = to_where_rules(conditions)
      builder = builder.where(rules, ctx) if rules
      Array(group_by_fields).each { |name| builder.group(data_field(name)) }
      builder.group(data_field(group_by)) if group_by.to_s.present?
      grouped = group_by.to_s.present? || Array(group_by_fields).any?
      builder.having(having.to_s.strip) if grouped && having.to_s.strip.present?

      metrics = normalize_aggregations(aggregations)
      if metrics.any?
        pairs = metrics.map do |agg_field, op|
          method = AGGREGATE_METHODS[op.to_s] || :sum
          ["#{op}_#{agg_field}", builder.public_send(method, agg_field)]
        end
        return pairs.to_h if result_format.to_s == "hash"

        pairs.first&.last
      else
        builder.aggregate((function || "sum").to_sym, field)
        records = builder.execute.records
        return { "#{function}_#{field}" => records } if result_format.to_s == "hash"

        records
      end
    end

    def writable_slugs(model_class)
      entity = model_class.respond_to?(:bound_entity) ? model_class.bound_entity : nil
      return [] unless entity

      writers = model_class.instance_methods
      Array(entity.property_schema_json).filter_map do |attribute|
        slug = attribute["name_slug"].to_s
        slug if slug.present? && writers.include?(:"#{slug}=")
      end
    end

    def relation_for(ctx_or_scope)
      return ctx_or_scope if ctx_or_scope.is_a?(ActiveRecord::Relation)

      scope(ctx_or_scope)
    end

    def known_slug?(relation, slug)
      entity = relation.klass.respond_to?(:bound_entity) ? relation.klass.bound_entity : nil
      return false unless entity

      Array(entity.property_schema_json).any? { |attribute| attribute["name_slug"].to_s == slug }
    end

    def assert_writable!(ctx, entry)
      raise Error, "entry is required" unless entry
      raise Error, "customer mismatch" unless entry.customer_id.to_s == ctx[:customer_id].to_s
    end

    def bridge_rows_pending?(ctx, entry)
      entry.new_record? && !ctx[:bridge_rows_saved] && ctx[:association_params].present? &&
        entry.equal?(ctx[:page_record])
    end

    def save_bridge_rows(ctx, entry)
      ctx[:bridge_rows_saved] = true
      errors = Pages::BridgeEntries.call(entry: entry, entity: ctx[:bound_entity], sections: ctx[:association_params],
                                         customer_id: ctx[:customer_id], audience: ctx[:audience])
      errors.empty? || record_failure(ctx, errors, [])
    end

    def record_failure(ctx, messages, fields)
      ctx[:errors] ||= []
      ctx[:error_details] ||= []
      Array(messages).map(&:to_s).each { |text| ctx[:errors] << text unless ctx[:errors].include?(text) }
      fields.each do |field|
        ctx[:error_details] << { "code" => "record_invalid", "field" => field.field, "message" => field.message,
                                 "full_message" => field.full_message, "details" => {} }
      end
      ctx[:error_details] << { "code" => "record_invalid", "field" => nil, "details" => {} } if fields.empty?
      false
    end

    def canonicalize(match)
      match.to_h.transform_keys(&:to_s).sort.to_h
    end

    def resolve_entity!(ctx, entity)
      return entity if entity.is_a?(Entity)
      return ctx && ctx[:bound_entity] if entity.blank?

      EntityResolver.named(entity, customer_id: ctx[:customer_id])
    rescue EntityResolver::Error => error
      raise Error, error.message
    end

    # Ownership.scope lets a member read every row of an open entity (no
    # person, owner or owned parent), but nobody owns those rows.
    def apply_own_scope(relation, ctx, entity)
      user_id = ctx && ctx[:current_user_id]
      return relation.none if user_id.blank? || ::People::Ownership.kind(entity) == :open

      user = ::Authentication::User.find_by(id: user_id, customer_id: ctx[:customer_id])
      return relation.none unless user

      owned = ::People::Ownership.scope(
        entity,
        viewer: user,
        audience: ::EntityAttributeAudience::MEMBER,
        customer_id: ctx[:customer_id]
      )
      relation.where(id: owned.select(:id))
    end

    def release_lock(tenant, lock_name, token)
      Lock.release(tenant, lock_name, token)
    rescue Lock::Error
      # NullStore (and other stores without compare-and-delete) expire via TTL.
      true
    end

    def blank_conditions?(conditions)
      return true if conditions.blank?
      return true if conditions.is_a?(Array) && conditions.empty?
      return false unless conditions.is_a?(Hash)
      return true if conditions["type"] == "group" && Array(conditions["conditions"]).empty?
      return true if conditions.key?("rules") && Array(conditions["rules"]).empty?

      false
    end

    def to_where_rules(conditions)
      return nil if blank_conditions?(conditions)

      case conditions
      when Array
        rules = conditions.filter_map { |row| pair_rule(row) }
        return nil if rules.empty?

        { "operator" => "AND", "rules" => rules }
      when Hash
        return conditions if conditions["rules"].is_a?(Array) && conditions["rules"].any?
        return decision_to_rules(conditions) if conditions["type"] == "group" || conditions["leftOperand"]
        return nil if conditions["type"]

        rules = conditions.filter_map { |key, value| { "field" => data_field(key), "op" => "==", "value" => value } }
        return nil if rules.empty?

        { "operator" => "AND", "rules" => rules }
      end
    end

    def decision_to_rules(condition)
      return nil if blank_conditions?(condition)
      return field_rule(condition) unless condition["type"] == "group"

      members = Array(condition["conditions"]).filter_map { |member| decision_to_rules(member) }
      return nil if members.empty?

      joins = Array(condition["joins"])
      if joins.uniq.size > 1
        members.drop(1).each_with_index.reduce(
          { "operator" => join_operator(joins[0]), "rules" => [members[0], members[1]].compact }
        ) do |acc, (rule, index)|
          { "operator" => join_operator(joins[index + 1]), "rules" => [acc, rule] }
        end
      else
        { "operator" => join_operator(joins.first), "rules" => members }
      end
    end

    def field_rule(row)
      left = row["leftOperand"].to_s
      return nil if left.blank? || left.start_with?("ctx.")

      { "field" => data_field(left), "op" => sql_operator(row["operator"]), "value" => row["rightOperand"] }
    end

    def pair_rule(row)
      return unless row.is_a?(Hash)

      key = row["key"] || row[:key]
      return if key.to_s.blank?

      { "field" => data_field(key), "op" => "==", "value" => row["value"] || row[:value] }
    end

    def join_operator(join)
      join.to_s.upcase == "OR" ? "OR" : "AND"
    end

    def sql_operator(operator)
      case operator.to_s
      when "!=", "<>" then "!="
      when ">", ">=", "<", "<=" then operator.to_s
      when "contains", "includes?" then "contains"
      when "is_empty", "blank?" then "blank?"
      when "is_not_empty", "present?" then "present?"
      when "in", "not_in" then operator.to_s
      else "=="
      end
    end

    def data_field(name)
      slug = name.to_s.delete_prefix("data.")
      return slug if slug == "id" || INTERNAL_COLUMNS.include?(slug)

      "data.#{slug}"
    end

    def apply_order(relation, field, direction)
      return relation if field.to_s.blank?

      dir = direction.to_s.downcase == "desc" ? "DESC" : "ASC"
      slug = field.to_s.delete_prefix("data.")
      if slug == "id" || INTERNAL_COLUMNS.include?(slug)
        relation.order(slug => dir.downcase.to_sym)
      else
        safe = JsonPathValidator.safe_json_path!(slug)
        relation.order(Arel.sql("json_extract(entity_entries.data, '$.#{safe}') #{dir}"))
      end
    end

    def apply_group(relation, field)
      return relation if field.to_s.blank?

      slug = field.to_s.delete_prefix("data.")
      if slug == "id" || INTERNAL_COLUMNS.include?(slug)
        relation.group(slug)
      else
        safe = JsonPathValidator.safe_json_path!(slug)
        relation.group(Arel.sql("json_extract(entity_entries.data, '$.#{safe}')"))
      end
    end

    def apply_limit(relation, limit, page, per_page, offset = nil)
      skip = [offset.to_i, 0].max
      if per_page
        size = [per_page.to_i, 1].max
        page_n = [page.to_i, 1].max
        return relation.limit(size).offset(skip + ((page_n - 1) * size))
      end
      relation = relation.offset(skip) if skip.positive?
      return relation.limit(limit.to_i) if limit.to_i.positive?

      relation
    end

    def round_numeric(value, digits)
      return value if digits.nil?

      case value
      when Numeric then value.round(digits.to_i)
      when Hash then value.transform_values { |item| round_numeric(item, digits) }
      else value
      end
    end

    def pagination_hash(total, page, per_page)
      return nil unless per_page && total

      size = [per_page.to_i, 1].max
      page_n = [page.to_i, 1].max
      {
        total_count: total,
        page: page_n,
        per_page: size,
        total_pages: (total.to_f / size).ceil,
        has_next: page_n * size < total
      }
    end

    def pluck_attributes(relation, slugs)
      raise Error, "select is required" if slugs.empty?

      slugs.each { |slug| assert_readable!(relation, slug) }
      records = relation.to_a
      if slugs.size == 1
        records.map { |entry| read_attr(entry, slugs.first) }
      else
        records.map { |entry| slugs.map { |slug| read_attr(entry, slug) } }
      end
    end

    def read_attr(entry, slug)
      return entry.id if slug.to_s == "id"
      return entry.public_send(slug) if entry.respond_to?(slug)

      raise UnknownAttribute, slug
    end

    def assert_readable!(relation, slug)
      return if slug.to_s == "id" || INTERNAL_COLUMNS.include?(slug.to_s)
      raise UnknownAttribute, slug unless known_slug?(relation, slug)
    end

    def count_expression(field)
      slug = field.to_s.delete_prefix("data.")
      return slug.to_sym if slug == "id" || INTERNAL_COLUMNS.include?(slug)

      safe = JsonPathValidator.safe_json_path!(slug)
      Arel.sql("json_extract(entity_entries.data, '$.#{safe}')")
    end

    def normalize_aggregations(raw)
      case raw
      when Hash
        raw.filter_map { |key, value| [key.to_s, value.to_s] if key.to_s.present? && value.to_s.present? }
      when Array
        raw.filter_map do |row|
          next unless row.is_a?(Hash)

          key = row["key"] || row[:key]
          value = row["value"] || row[:value]
          [key.to_s, value.to_s] if key.to_s.present? && value.to_s.present?
        end
      else
        []
      end
    end

    private_class_method :relation_for, :known_slug?, :assert_writable!,
      :bridge_rows_pending?, :save_bridge_rows, :record_failure, :canonicalize,
      :release_lock, :with_adjust_lock, :blank_conditions?, :to_where_rules, :decision_to_rules, :field_rule,
      :pair_rule, :join_operator, :sql_operator, :data_field, :apply_group,
      :apply_limit, :pagination_hash, :pluck_attributes, :read_attr, :assert_readable!,
      :count_expression, :normalize_aggregations, :compute_aggregate, :round_numeric,
      :empty_value?, :reference_slugs, :reference_value, :resolve_entity!, :apply_own_scope
  end
end
