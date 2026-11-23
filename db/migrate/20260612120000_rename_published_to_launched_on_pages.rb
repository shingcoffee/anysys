# frozen_string_literal: true

class RenamePublishedToLaunchedOnPages < ActiveRecord::Migration[8.1]
  def change
    rename_column :pages, :published, :launched
  end
end
