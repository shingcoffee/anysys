# frozen_string_literal: true

class RenamePagesPublicTokenToPublicUuid < ActiveRecord::Migration[8.1]
  UUID_RE = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i

  def up
    rename_column :pages, :public_token, :public_uuid

    say_with_time "normalize pages.public_uuid to SecureRandom.uuid" do
      # Unscoped: include soft-deleted rows so the unique index stays clean.
      # Intentional hard cutover: former hex public_token values are not UUIDs
      # and are regenerated. Existing /forms/:token bookmarks will break.
      Page.unscoped.find_each do |page|
        next if page.public_uuid.to_s.match?(UUID_RE)

        page.update_columns(public_uuid: SecureRandom.uuid)
      end
    end
  end

  # Irreversible for token values: down restores the column name only.
  def down
    rename_column :pages, :public_uuid, :public_token
  end
end
