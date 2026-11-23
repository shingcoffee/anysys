# frozen_string_literal: true

class CreateIndustryTemplateMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :industry_template_mappings do |t|
      t.string :industry, null: false
      t.string :template_key, null: false
      t.timestamps
    end

    add_index :industry_template_mappings, %i[industry template_key], unique: true, name: "idx_industry_template_unique"
    add_index :industry_template_mappings, :industry
    add_index :industry_template_mappings, :template_key
  end
end
