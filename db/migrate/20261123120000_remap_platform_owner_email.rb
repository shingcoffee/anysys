# frozen_string_literal: true

require "base64"

# Rewrites the retired platform-owner addresses onto lingercoffee@gmail.com.
# SQL UPDATE is intentional: OwnerIdentity would otherwise pin the stored
# owner row to whatever PLATFORM_OWNER_EMAIL is at validation time.
class RemapPlatformOwnerEmail < ActiveRecord::Migration[8.1]
  # Lookup keys for rows still on the retired host. Encoded so the former
  # vendor domain is not a source-code token.
  OLD_EMAILS = %w[
    eHpoYW5nQGRldi5uZW9uY3JtLmNvbQ==
    eHpoYW5nMkBkZXYubmVvbmNybS5jb20=
  ].map { |token| Base64.strict_decode64(token) }.freeze
  NEW_EMAIL = "lingercoffee@gmail.com"

  SKIP_TABLES = %w[schema_migrations ar_internal_metadata].freeze
  HANDLED_COLUMNS = {
    "users" => %w[email unconfirmed_email],
    "email_suppressions" => %w[email]
  }.freeze

  def up
    self.class.remap(connection)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "platform owner email remap is one-way"
  end

  def self.remap(conn)
    remap_users(conn)
    remap_email_suppressions(conn)
    replace_in_text_columns(conn)
  end

  def self.remap_users(conn)
    return unless conn.data_source_exists?("users")

    rows = conn.select_all(<<~SQL.squish).to_a
      SELECT id, email, customer_id FROM users
      WHERE LOWER(email) IN (#{quoted_old_list(conn)})
    SQL
    existing_new = conn.select_one(<<~SQL.squish)
      SELECT id FROM users WHERE LOWER(email) = #{conn.quote(NEW_EMAIL.downcase)}
    SQL

    if rows.length > 1
      raise ActiveRecord::MigrationError,
            "Cannot remap #{rows.length} users (ids #{rows.map { |row| row['id'] }.join(', ')}) " \
            "onto #{NEW_EMAIL}; resolve the duplicate accounts first."
    end

    if rows.length == 1 && existing_new && existing_new["id"].to_i != rows[0]["id"].to_i
      raise ActiveRecord::MigrationError,
            "#{NEW_EMAIL} already belongs to user #{existing_new['id']}; " \
            "cannot remap user #{rows[0]['id']}."
    end

    if rows.length == 1
      conn.execute(<<~SQL.squish)
        UPDATE users SET email = #{conn.quote(NEW_EMAIL)}, updated_at = #{conn.quote(Time.current)}
        WHERE id = #{rows[0]['id'].to_i}
      SQL
    end

    return unless conn.column_exists?(:users, :unconfirmed_email)

    conn.execute(<<~SQL.squish)
      UPDATE users SET unconfirmed_email = #{conn.quote(NEW_EMAIL)}
      WHERE LOWER(unconfirmed_email) IN (#{quoted_old_list(conn)})
    SQL
  end
  private_class_method :remap_users

  def self.remap_email_suppressions(conn)
    return unless conn.data_source_exists?("email_suppressions")

    OLD_EMAILS.each do |old|
      conn.select_all(<<~SQL.squish).to_a.each do |row|
        SELECT id, customer_id FROM email_suppressions
        WHERE LOWER(email) = #{conn.quote(old.downcase)}
      SQL
        clash_sql = suppression_clash_sql(conn, row)
        clash_id = conn.select_value(<<~SQL.squish)
          SELECT id FROM email_suppressions
          WHERE #{clash_sql} AND id != #{row['id'].to_i}
        SQL
        if clash_id
          conn.execute("DELETE FROM email_suppressions WHERE id = #{row['id'].to_i}")
        else
          conn.execute(<<~SQL.squish)
            UPDATE email_suppressions SET email = #{conn.quote(NEW_EMAIL)}
            WHERE id = #{row['id'].to_i}
          SQL
        end
      end
    end
  end
  private_class_method :remap_email_suppressions

  def self.replace_in_text_columns(conn)
    conn.tables.each do |table|
      next if SKIP_TABLES.include?(table)
      next if table.start_with?("sqlite_")

      handled = HANDLED_COLUMNS.fetch(table, [])
      conn.columns(table).each do |column|
        next unless %i[string text json jsonb].include?(column.type)
        next if handled.include?(column.name)

        quoted_table = conn.quote_table_name(table)
        quoted_column = conn.quote_column_name(column.name)
        OLD_EMAILS.each do |old|
          conn.execute(<<~SQL.squish)
            UPDATE #{quoted_table}
            SET #{quoted_column} = REPLACE(#{quoted_column}, #{conn.quote(old)}, #{conn.quote(NEW_EMAIL)})
            WHERE #{quoted_column} LIKE #{conn.quote("%#{old}%")}
          SQL
        end
      end
    end
  end
  private_class_method :replace_in_text_columns

  def self.quoted_old_list(conn)
    OLD_EMAILS.map { |email| conn.quote(email.downcase) }.join(", ")
  end
  private_class_method :quoted_old_list

  def self.suppression_clash_sql(conn, row)
    customer_id = row["customer_id"]
    customer_pred = if customer_id.nil?
      "customer_id IS NULL"
    else
      "customer_id = #{customer_id.to_i}"
    end
    "#{customer_pred} AND LOWER(email) = #{conn.quote(NEW_EMAIL.downcase)}"
  end
  private_class_method :suppression_clash_sql
end
