# frozen_string_literal: true

# Restore static/dynamic list types and embedded segment_rules so audience lists
# can filter contacts by conditions again. Rules live on the list itself — the
# separate email_segments table / Segments admin surface stays removed.
class RestoreEmailListConditionalFilters < ActiveRecord::Migration[8.1]
  def change
    add_column :email_lists, :list_type, :string, null: false, default: "static"
    add_column :email_lists, :segment_rules, :json, null: false, default: {}
  end
end
