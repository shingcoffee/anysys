# frozen_string_literal: true

class AddBasedOnVersionToPageVersions < ActiveRecord::Migration[8.1]
  def up
    add_reference :page_versions, :based_on_version,
                  foreign_key: { to_table: :page_versions, on_delete: :nullify }, index: true
  end

  def down
    remove_reference :page_versions, :based_on_version
  end
end
