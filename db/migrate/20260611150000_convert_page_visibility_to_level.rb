# frozen_string_literal: true

# Collapses the three-boolean visibility JSON into a single hierarchical
# level string: "admin" (floor) < "member" < "public". Existing rows are
# normalised widest-flag-wins before the JSON column is dropped.
class ConvertPageVisibilityToLevel < ActiveRecord::Migration[8.1]
  def up
    add_column :pages, :visibility_level, :string, null: false, default: "admin"

    execute(<<~SQL.squish)
      UPDATE pages SET visibility_level =
        CASE
          WHEN visibility LIKE '%"public":true%' THEN 'public'
          WHEN visibility LIKE '%"member":true%' THEN 'member'
          ELSE 'admin'
        END
    SQL

    remove_column :pages, :visibility
    rename_column :pages, :visibility_level, :visibility
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
