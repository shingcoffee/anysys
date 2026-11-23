# frozen_string_literal: true

class AddPublishingToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :published,    :boolean, default: false, null: false
    add_column :pages, :public_token, :string
    add_index  :pages, :public_token, unique: true
  end
end
