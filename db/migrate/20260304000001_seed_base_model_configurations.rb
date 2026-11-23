# frozen_string_literal: true

class SeedBaseModelConfigurations < ActiveRecord::Migration[8.0]
  def up
    # Find all models that include the Extendable concern and seed configurations
    Rails.application.eager_load!

    ApplicationRecord.descendants.each do |model|
      next unless model.included_modules.include?(Extendable)

      field_configs = {}
      system_fields = %w[id customer_id status created_at updated_at]

      model.columns.each do |column|
        next if system_fields.include?(column.name)

        field_configs[column.name] = suggest_html_type(column)
      end

      now = Time.current.iso8601
      execute <<-SQL.squish
        INSERT INTO base_model_configurations (base_class_name, extendable, field_configurations, created_at, updated_at)
        VALUES (#{quote(model.name)}, #{quote(true)}, #{quote(field_configs.to_json)}, #{quote(now)}, #{quote(now)})
      SQL
    end
  end

  def down
    execute "DELETE FROM base_model_configurations"
  end

  private

  def suggest_html_type(column)
    name = column.name.downcase

    # Name-based heuristics first
    return "email" if name.include?("email")
    return "tel" if name.include?("phone") || name.include?("mobile") || name.include?("fax")
    return "url" if name.include?("url") || name.include?("website") || name.include?("homepage")
    return "select" if name.include?("gender") || name.include?("role") || name.include?("tier") || name.include?("type") || name.include?("category")
    return "textarea" if name.include?("description") || name.include?("bio") || name.include?("notes") || name.include?("comment") || name.include?("address")
    return "password" if name.include?("password")
    return "color" if name.include?("color") || name.include?("colour")
    return "image" if name.include?("avatar") || name.include?("photo") || name.include?("image")

    # Column type fallback
    case column.type
    when :string then "text"
    when :text then "textarea"
    when :integer, :decimal, :float then "number"
    when :boolean then "checkbox"
    when :date then "date"
    when :datetime then "datetime-local"
    when :time then "time"
    else "text"
    end
  end
end
