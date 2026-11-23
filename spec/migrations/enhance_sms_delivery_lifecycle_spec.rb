# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require Rails.root.join("db/migrate/20261011173041_harden_email_sms_backend_lifecycle")
require Rails.root.join("db/migrate/20261013000100_enhance_sms_delivery_lifecycle")

module SmsEnhancementMigrationDatabase
  class Record < ActiveRecord::Base
    self.abstract_class = true
  end

  SCHEMA_REVISION = "91b89d3e"
  TABLES = %w[customers sms_templates sms_credentials sms_messages email_credentials email_messages email_send_activities].freeze
end

RSpec.describe EnhanceSmsDeliveryLifecycle do
  self.use_transactional_tests = false

  around do |example|
    @application_pool = ActiveRecord::Base.connection_pool
    @application_config = ActiveRecord::Base.connection_db_config
    Dir.mktmpdir("sms-enhancement-", Rails.root.join("tmp").to_s) do |directory|
      @database_config = { adapter: "sqlite3", database: File.join(directory, "migration.sqlite3"), timeout: 5000 }
      SmsEnhancementMigrationDatabase::Record.establish_connection(@database_config)
      SmsEnhancementMigrationDatabase::Record.connection_pool.with_connection do |connection|
        @connection = connection
        load_predecessor_schema
        example.run
      end
    ensure
      SmsEnhancementMigrationDatabase::Record.remove_connection
      @connection = @database_config = nil
    end
  end

  def migrate!(migration_class = described_class, direction: :up)
    @connection.transaction do
      migration = migration_class.new
      migration.suppress_messages { migration.exec_migration(@connection, direction) }
    end
  end

  def load_predecessor_schema
    source, error, status = Open3.capture3("git", "show", "#{SmsEnhancementMigrationDatabase::SCHEMA_REVISION}:db/schema.rb", chdir: Rails.root.to_s)
    raise "Cannot load pinned predecessor schema: #{error}" unless status.success?

    SmsEnhancementMigrationDatabase::TABLES.each do |table|
      definition = source[/^  create_table "#{Regexp.escape(table)}"[^\n]*\n.*?^  end$/m]
      raise "Pinned predecessor schema is missing #{table}" unless definition

      @connection.instance_eval(definition, "#{SmsEnhancementMigrationDatabase::SCHEMA_REVISION}:db/schema.rb")
    end
    source.each_line do |line|
      match = /^  add_foreign_key "([^"]+)", "([^"]+)"/.match(line)
      next unless match && [match[1], match[2]].all? { |table| SmsEnhancementMigrationDatabase::TABLES.include?(table) }

      @connection.instance_eval(line)
    end
    # Replay the actual earlier additive migration, rather than recreating its
    # metadata, receipt tables and indexes from today's schema dump.
    migrate!(HardenEmailSmsBackendLifecycle)
    @connection.execute("INSERT INTO customers (id, name, created_at, updated_at) VALUES (4001, 'Historical tenant', '2026-10-01 10:00:00', '2026-10-01 10:00:00')")
    @connection.execute("INSERT INTO customers (id, name, created_at, updated_at) VALUES (4002, 'Other tenant', '2026-10-01 10:00:00', '2026-10-01 10:00:00')")
  end

  def insert_message(id:, status: nil, customer_id: 4001, key: "historical-#{id}", **attributes)
    row = { id: id, customer_id: customer_id, to: "+8613800138000", template_key: "historical_notice",
            vars: '{"code":"keep"}', provider: "aliyun", idempotency_key: key,
            raw_response: '{"vendor":"original"}', metadata: '{"credential_id":123,"caller":"historical"}',
            created_at: "2026-10-01 10:00:00", updated_at: "2026-10-01 10:01:00" }.merge(attributes)
    row[:status] = status if status
    columns = row.keys.map { |name| @connection.quote_column_name(name) }.join(",")
    values = row.values.map { |value| @connection.quote(value) }.join(",")
    @connection.execute("INSERT INTO sms_messages (#{columns}) VALUES (#{values})")
  end

  def rows
    @connection.select_all("SELECT * FROM sms_messages ORDER BY id").to_a
  end

  def index_facts
    @connection.indexes(:sms_messages).to_h do |index|
      [index.name, { columns: index.columns, unique: index.unique, where: index.where }]
    end
  end

  it "migrates a disposable database without replacing the application connection or altering its SMS schema" do
    application_connection = ActiveRecord::Base.connection
    original_schema = application_connection.select_value("SELECT sql FROM sqlite_master WHERE name = 'sms_messages'")
    expect(@connection).not_to equal(application_connection)
    expect(@connection.pool.db_config.database).not_to eq(@application_config.database)
    migrate!
    expect(ActiveRecord::Base.connection_pool).to equal(@application_pool)
    expect(ActiveRecord::Base.connection_db_config).to equal(@application_config)
    expect(application_connection.select_value("SELECT sql FROM sqlite_master WHERE name = 'sms_messages'")).to eq(original_schema)
  end

  it "preserves historical pending, accepted and terminal rows while adding inert dispatch fields" do
    %w[pending sent delivered failed unknown suppressed].each_with_index do |status, i|
      insert_message(id: i + 1, status: status, vendor_message_id: "OLD_#{i}", sent_at: "2026-10-01 10:01:00",
                     delivered_at: status == "delivered" ? "2026-10-01 10:02:00" : nil,
                     failure_code: status == "failed" ? "OLD_FAILURE" : nil)
    end
    original_rows = rows
    original_columns = @connection.columns(:sms_messages).map(&:name)
    original_indexes = index_facts
    original_foreign_keys = @connection.foreign_keys(:sms_messages).map { |key| [key.to_table, key.column] }
    migrate!

    expect(rows.map { |row| row.slice(*original_columns) }).to eq(original_rows)
    expect(rows).to all(include("expires_at" => nil, "delivery_enqueued_at" => nil, "delivery_claimed_at" => nil,
                               "delivery_claim_token" => nil, "dispatch_started_at" => nil, "delivery_attempts" => 0))
    expect(index_facts.slice(*original_indexes.keys)).to eq(original_indexes)
    expect(@connection.foreign_keys(:sms_messages).map { |key| [key.to_table, key.column] }).to match_array(original_foreign_keys)
  end

  it "changes only the new-row status default, leaves expiry admission-owned, and retains real tenant idempotency uniqueness" do
    insert_message(id: 1)
    migrate!
    insert_message(id: 2, key: "new-default")
    columns = @connection.columns(:sms_messages).index_by(&:name)
    expect(rows.map { |row| row.fetch("status") }).to eq(%w[pending queued])
    expect(columns.fetch("status").default).to eq("queued")
    expect(columns.fetch("expires_at").default).to be_nil
    expect(columns.fetch("expires_at").null).to be(true)
    expect(columns.fetch("delivery_attempts").default.to_i).to eq(0)
    expect(columns.fetch("delivery_attempts").null).to be(false)
    expect(index_facts.fetch("idx_sms_delivery_outbox")).to eq(columns: %w[status dispatch_started_at delivery_enqueued_at], unique: false, where: nil)

    expect { insert_message(id: 3, key: "new-default") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert_message(id: 3, customer_id: 4002, key: "new-default") }.not_to raise_error
    expect { insert_message(id: 4, key: nil); insert_message(id: 5, key: nil) }.not_to raise_error
  end

  it "leaves historical pending rows outside the queued outbox without enqueueing or recording a dispatch" do
    insert_message(id: 1, status: "pending", vendor_message_id: nil)
    insert_message(id: 2, status: "pending", vendor_message_id: "OLD_ACCEPTED")
    original_rows = rows
    original_jobs = enqueued_jobs.deep_dup
    migrate!

    # This fixture ends at 20261013000100. Validate the migration's persisted
    # safety boundary directly; current recovery requires later campaign columns
    # and belongs in the outbox specs against the complete application schema.
    expect(enqueued_jobs).to eq(original_jobs)
    expect(rows).to all(include("status" => "pending", "delivery_attempts" => 0, "dispatch_started_at" => nil,
                               "expires_at" => nil, "delivery_enqueued_at" => nil,
                               "delivery_claimed_at" => nil, "delivery_claim_token" => nil))
    expect(@connection.select_values("SELECT id FROM sms_messages WHERE status = 'queued' AND dispatch_started_at IS NULL")).to be_empty
    expect(rows.map { |row| row.slice(*original_rows.first.keys) }).to eq(original_rows)
  end

  it "rolls back its schema additions without deleting historical rows or predecessor indexes" do
    insert_message(id: 1, status: "pending")
    insert_message(id: 2, status: "delivered", delivered_at: "2026-10-01 10:02:00")
    original_rows = rows
    original_columns = @connection.columns(:sms_messages).map(&:name)
    original_indexes = index_facts
    migrate!
    migrate!(direction: :down)
    expect(rows).to eq(original_rows)
    expect(@connection.columns(:sms_messages).map(&:name)).to eq(original_columns)
    expect(index_facts).to eq(original_indexes)
    expect(@connection.columns(:sms_messages).find { |column| column.name == "status" }.default).to eq("pending")
  end
end
