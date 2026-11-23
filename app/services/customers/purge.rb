# frozen_string_literal: true

module Customers
  # Physical tenant deletion is a database operation: enumerate owned rows
  # without default scopes, follow dependent foreign keys, and delete in a
  # single transaction. Rails' association list alone misses soft-deleted rows,
  # module records, and overrides of shared parents. Use ActiveRecord schema
  # metadata rather than duplicating every module's associations here.
  class Purge
    Result = Struct.new(:ok, :customer_ids, :counts, :dependencies, :error_code, keyword_init: true) do
      def success? = ok
      def deleted_count = counts.fetch("customers", 0)
    end

    class DependencyError < StandardError; end

    class Row < ApplicationRecord
      self.abstract_class = true
    end

    # Some historical tables lack SQL constraints. Include their logical
    # version/content/head edges in both dependency ordering and content GC.
    VERSION_TABLES = {
      "entity_versions" => ["entities", "entity_definition_contents", "entity_id"],
      "page_versions" => ["pages", "page_configuration_contents", "page_id"],
      "flowchart_versions" => ["flowcharts", "flowchart_configuration_contents", "flowchart_id"],
      "email_template_versions" => ["email_templates", "email_template_contents", "email_template_id"]
    }.freeze

    def self.call(customers:, delete_customers: true)
      new(customers: customers, delete_customers: delete_customers).call
    end

    def self.dependencies(customers:)
      new(customers: customers).dependencies
    end

    def initialize(customers:, delete_customers: true)
      @customer_ids = if customers.is_a?(ActiveRecord::Relation)
        customers.pluck(:id)
      else
        Array(customers).map { |customer| customer.respond_to?(:id) ? customer.id : customer }
      end.compact.uniq
      @delete_customers = delete_customers
      # Empty-trash deletes the customer row. Dependent cleanup before a hard
      # destroy (delete_customers: false) must still run, including in tests
      # that remove 81721200 to simulate its absence.
      protected_id = Authentication::User::PLATFORM_CUSTOMER_ID
      @skipped_platform = @delete_customers && @customer_ids.any? { |id| id.to_i == protected_id }
      @customer_ids = @customer_ids.reject { |id| id.to_i == protected_id } if @skipped_platform
      @connection = Customer.connection
      @models = {}
      @plan = Hash.new { |hash, table| hash[table] = Set.new }
      @blockers = []
    end

    def call
      if @customer_ids.empty? && @skipped_platform
        return Result.new(ok: false, customer_ids: [], counts: {}, dependencies: nil, error_code: :platform_customer)
      end

      report = nil
      counts = {}
      Customer.transaction(requires_new: true) do
        found = Customer.unscoped.where(id: @customer_ids).lock.ids
        raise ActiveRecord::RecordNotFound unless found.to_set == @customer_ids.to_set

        report = dependencies
        raise DependencyError if @blockers.any?

        nullify_internal_pointers
        deletion_order.each do |table|
          counts[table] = model(table).where(id: @plan[table].to_a).delete_all
        end
      end
      Result.new(ok: true, customer_ids: @customer_ids, counts: counts, dependencies: report)
    rescue DependencyError, ActiveRecord::ActiveRecordError => error
      code = error.is_a?(DependencyError) ? :foreign_dependency : :purge_failed
      Result.new(ok: false, customer_ids: [], counts: {}, dependencies: report, error_code: code)
    end

    def dependencies
      build_plan
      {
        customer_ids: @customer_ids,
        counts: @plan.reject { |_, ids| ids.empty? }.transform_values(&:size),
        blockers: @blockers.deep_dup
      }
    end

    private

    def model(table)
      @models[table] ||= Class.new(Row) do
        self.table_name = table
        self.inheritance_column = :_purge_type
      end
    end

    def columns(table)
      model(table).columns_hash
    end

    def tables
      @tables ||= @connection.tables.select { |table| @connection.primary_key(table) == "id" }
    end

    def edges
      @edges ||= begin
        definitions = tables.flat_map do |table|
          @connection.foreign_keys(table).map do |key|
            { from: table, to: key.to_table, column: key.column }
          end
        end
        VERSION_TABLES.each do |version, (parent, content, parent_key)|
          next unless tables.include?(version)

          definitions << { from: version, to: parent, column: parent_key }
          definitions << { from: version, to: content, column: "content_id" }
          definitions << { from: parent, to: version, column: "current_version_id" }
          head = parent.singularize + "_customer_heads"
          definitions << { from: head, to: version, column: "current_version_id" } if tables.include?(head)
        end
        definitions.uniq
      end
    end

    def build_plan
      @plan.clear
      @blockers.clear
      tables.each do |table|
        next unless columns(table).key?("customer_id")

        @plan[table].merge(model(table).where(customer_id: @customer_ids).ids)
      end
      @plan["customers"].merge(@customer_ids) if @delete_customers
      preserve_referenced_content

      loop do
        before = @plan.values.sum(&:size)
        edges.each do |edge|
          target_ids = @plan[edge[:to]]
          next if target_ids.empty?

          dependents = model(edge[:from]).where(edge[:column] => target_ids.to_a)
          if columns(edge[:from]).key?("customer_id")
            owned = dependents.where(customer_id: @customer_ids)
            @plan[edge[:from]].merge(owned.ids)
            foreign_ids = dependents.where.not(id: @plan[edge[:from]].to_a).ids
            @blockers << { table: edge[:from], ids: foreign_ids, referenced_table: edge[:to] } if foreign_ids.any?
          else
            @plan[edge[:from]].merge(dependents.ids)
          end
        end
        add_polymorphic_dependents
        break if before == @plan.values.sum(&:size)
      end
      @blockers.uniq!
    end

    def preserve_referenced_content
      VERSION_TABLES.each do |version, (_, content, _)|
        next unless tables.include?(version) && tables.include?(content)

        remaining = model(version).where.not(id: @plan[version].to_a).distinct.pluck(:content_id)
        @plan[content].subtract(remaining)
      end
    end

    def add_polymorphic_dependents
      %w[active_storage_attachments action_text_rich_texts].each do |table|
        next unless tables.include?(table)

        model(table).distinct.pluck(:record_type).each do |type|
          klass = type.safe_constantize
          next unless klass.is_a?(Class) && klass < ActiveRecord::Base

          ids = @plan[klass.table_name]
          next if ids.empty?

          @plan[table].merge(model(table).where(record_type: type, record_id: ids.to_a).ids)
        end
      end
    end

    def nullify_internal_pointers
      edges.each do |edge|
        next unless columns(edge[:from]).fetch(edge[:column]).null
        next if @plan[edge[:from]].empty? || @plan[edge[:to]].empty?

        model(edge[:from]).where(id: @plan[edge[:from]].to_a)
                          .where(edge[:column] => @plan[edge[:to]].to_a)
                          .update_all(edge[:column] => nil)
      end
    end

    def deletion_order
      remaining = @plan.select { |_, ids| ids.any? }.keys
      ordered = []
      until remaining.empty?
        leaves = remaining.reject do |table|
          edges.any? do |edge|
            next false unless edge[:to] == table && remaining.include?(edge[:from])

            model(edge[:from]).where(id: @plan[edge[:from]].to_a)
                              .where(edge[:column] => @plan[table].to_a).exists?
          end
        end
        raise DependencyError if leaves.empty?

        ordered.concat(leaves)
        remaining -= leaves
      end
      ordered
    end
  end
end
