# frozen_string_literal: true

class MakeUsersEmailGloballyUnique < ActiveRecord::Migration[8.1]
  def up
    uniquify_duplicate_emails

    remove_index :users, name: "index_users_on_customer_id_and_email"
    remove_index :users, name: "index_users_on_email"
    add_index :users, "LOWER(email)", unique: true, name: "index_users_on_lower_email"
  end

  def down
    remove_index :users, name: "index_users_on_lower_email"
    add_index :users, :email, name: "index_users_on_email"
    add_index :users, [ :customer_id, :email ], unique: true, name: "index_users_on_customer_id_and_email"
  end

  private

  # Keep the oldest row's address; rewrite later duplicates so the unique
  # index can be added. Sign-in never picks a "winner" among duplicates —
  # after this rewrite there is only one row per original address.
  def uniquify_duplicate_emails
    duplicate_emails = select_values(<<~SQL.squish)
      SELECT LOWER(email) FROM users GROUP BY LOWER(email) HAVING COUNT(*) > 1
    SQL

    duplicate_emails.each do |email|
      ids = select_values(<<~SQL.squish)
        SELECT id FROM users WHERE LOWER(email) = #{quote(email)} ORDER BY id
      SQL
      ids.drop(1).each do |id|
        current = select_value("SELECT email FROM users WHERE id = #{quote(id)}")
        local, domain = current.to_s.split("@", 2)
        next if domain.blank?

        execute(<<~SQL.squish)
          UPDATE users SET email = #{quote("#{local}+#{id}@#{domain}")} WHERE id = #{quote(id)}
        SQL
      end
    end
  end
end
