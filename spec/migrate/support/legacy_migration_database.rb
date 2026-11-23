# frozen_string_literal: true

require "open3"
require "tmpdir"
require "json"

# Evaluate the original dumped table definitions, not today's application models
# or a hand-maintained approximation of the pre-migration schema.
module LegacyMigrationDatabase
  SCHEMA_REVISION = "91b89d3e"
  TABLES = %w[
    customers users billing_countable_items billing_coupons billing_invoice_line_items
    billing_invoices billing_payment_methods billing_plan_limits billing_plans
    billing_settings billing_subscriptions payment_merchant_accounts payment_methods
    payment_orders payment_refunds payment_subscriptions payment_webhook_events payments
  ].freeze

  class Record < ActiveRecord::Base
    self.abstract_class = true
  end

  def self.schema_source
    @schema_source ||= begin
      source, error, status = Open3.capture3("git", "show", "#{SCHEMA_REVISION}:db/schema.rb", chdir: Rails.root.to_s)
      raise "Cannot load pinned migration schema: #{error}" unless status.success?

      source.freeze
    end
  end

  def with_legacy_migration_database
    application_pool = ActiveRecord::Base.connection_pool
    application_config = ActiveRecord::Base.connection_db_config
    Dir.mktmpdir("anysys-migration-", Rails.root.join("tmp").to_s) do |directory|
      config = { adapter: "sqlite3", database: File.join(directory, "legacy.sqlite3"), timeout: 5000,
                 pragmas: { journal_mode: "memory", synchronous: "off" } }
      Record.establish_connection(config)
      Record.connection_pool.with_connection do |connection|
        @legacy_connection = connection
        @legacy_database_config = config
        load_legacy_schema
        yield
      end
    ensure
      Record.remove_connection
      @legacy_connection = @legacy_database_config = nil
      expect(ActiveRecord::Base.connection_pool).to equal(application_pool)
      expect(ActiveRecord::Base.connection_db_config).to equal(application_config)
    end
  end

  def legacy_connection = @legacy_connection

  def load_legacy_schema
    source = LegacyMigrationDatabase.schema_source
    TABLES.each do |table|
      definition = source[/^  create_table "#{Regexp.escape(table)}"[^\n]*\n.*?^  end$/m]
      raise "Pinned schema is missing #{table}" unless definition

      legacy_connection.instance_eval(definition, "#{SCHEMA_REVISION}:db/schema.rb")
    end
    source.each_line do |line|
      match = /^  add_foreign_key "([^"]+)", "([^"]+)"/.match(line)
      next unless match && TABLES.include?(match[1]) && TABLES.include?(match[2])

      legacy_connection.instance_eval(line, "#{SCHEMA_REVISION}:db/schema.rb")
    end
  end

  def legacy_insert(table, **attributes)
    timestamps = legacy_connection.columns(table).map(&:name) & %w[created_at updated_at]
    row = timestamps.to_h { |column| [column, "2026-01-31 12:00:00"] }.merge(attributes.stringify_keys)
    columns = row.keys.map { |column| legacy_connection.quote_column_name(column) }.join(",")
    values = row.values.map { |value| legacy_connection.quote(value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value) }.join(",")
    legacy_connection.insert("INSERT INTO #{legacy_connection.quote_table_name(table)} (#{columns}) VALUES (#{values})")
  end

  def legacy_rows(table, columns: "*")
    legacy_connection.select_all("SELECT #{columns} FROM #{legacy_connection.quote_table_name(table)} ORDER BY id").to_a
  end

  def legacy_schema_state
    legacy_connection.select_all("SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name").to_a
  end

  def migrate_legacy!(migration_class, direction: :up)
    migration = migration_class.new
    legacy_connection.transaction do
      migration.suppress_messages { migration.exec_migration(legacy_connection, direction) }
    end
  end

  # The payment data repair's private Row classes and transaction inherit Base.
  # Run that exact code in a child process against this file. Never reconnect
  # Base (or stub its database methods) in the RSpec process.
  def migrate_legacy_in_child!(migration_class, direction: :up)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      begin
        ActiveRecord::Base.establish_connection(@legacy_database_config)
        connection = ActiveRecord::Base.connection
        migration = migration_class.new
        connection.transaction do
          migration.suppress_messages { migration.exec_migration(connection, direction) }
        end
        Marshal.dump(nil, writer)
      rescue StandardError => error
        Marshal.dump([error.class.name, error.message, error.backtrace], writer)
      ensure
        writer.close
        exit! 0
      end
    end
    writer.close
    failure = Marshal.load(reader)
    Process.wait(pid)
    if failure
      error = failure[0].constantize.new(failure[1])
      error.set_backtrace(failure[2])
      raise error
    end
  ensure
    reader&.close
    writer&.close unless writer&.closed?
  end
end
