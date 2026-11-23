# frozen_string_literal: true

class RemoveListTypeFromEmailLists < ActiveRecord::Migration[8.1]
  def change
    remove_column :email_lists, :list_type, :string, default: "static", null: false
  end
end
