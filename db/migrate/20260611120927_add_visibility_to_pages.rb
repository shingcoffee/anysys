# frozen_string_literal: true

class AddVisibilityToPages < ActiveRecord::Migration[8.1]
  # Single JSON column holding the page's audience visibility, mirroring the
  # entity-field `visibility` shape: { "admin" => bool, "member" => bool,
  # "public" => bool }. Defaults to admin-only (secure by default).
  DEFAULT_VISIBILITY = '{"admin":true,"member":false,"public":false}'

  def change
    add_column :pages, :visibility, :text, null: false, default: DEFAULT_VISIBILITY
  end
end
