# frozen_string_literal: true

class AddCategoryAndStreamIdToEmailTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :email_templates, :category, :string
    add_reference :email_templates, :email_stream, foreign_key: true, index: true
  end
end
