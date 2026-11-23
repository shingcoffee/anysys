# frozen_string_literal: true

class ModuleModelDiscovery
  MODULE_DIRECTORY_MAPPINGS = {
    "authentication" => ["app/models/authentication"],
    "email"          => ["app/models/emails"],
    "payment"        => ["app/models/payments"],
    "sms"            => ["app/models/sms"],
    "captcha"        => ["app/models/captcha"]
  }.freeze

  EXTRA_MODULE_CLASSES = {
    "authentication" => ["Role", "RolePermission", "UsersRole"]
  }.freeze

  def self.call(module_key)
    new(module_key).call
  end

  def initialize(module_key)
    @module_key = module_key.to_s
  end

  def call
    models = discover_directory_models + discover_extra_models
    models.compact.uniq { |m| m[:name] }.sort_by { |m| m[:name] }
  end

  private

  def discover_directory_models
    dirs = MODULE_DIRECTORY_MAPPINGS[@module_key] || ["app/models/#{@module_key}"]
    dirs.flat_map do |rel_dir|
      model_dir = Rails.root.join(rel_dir)
      next [] unless model_dir.directory?

      Dir.glob(model_dir.join("**", "*.rb")).filter_map do |file_path|
        class_name = derive_class_name(file_path)
        klass = class_name.safe_constantize
        next unless klass && klass < ApplicationRecord

        build_model_hash(klass)
      rescue StandardError
        nil
      end
    end
  end

  def discover_extra_models
    class_names = EXTRA_MODULE_CLASSES[@module_key] || []
    class_names.filter_map do |cname|
      klass = cname.safe_constantize
      next unless klass && klass < ApplicationRecord

      build_model_hash(klass)
    rescue StandardError
      nil
    end
  end

  def derive_class_name(file_path)
    relative = Pathname.new(file_path).relative_path_from(Rails.root.join("app", "models"))
    relative.to_s.delete_suffix(".rb").camelize
  end

  def build_model_hash(klass)
    {
      name: klass.name,
      table_name: klass.table_name,
      columns_count: klass.columns.size,
      columns: extract_columns(klass),
      associations_count: klass.reflect_on_all_associations.size,
      associations: extract_associations(klass)
    }
  end

  def extract_columns(klass)
    klass.columns.filter_map do |col|
      next if Authentication::User::SENSITIVE_COLUMNS.include?(col.name)

      {
        name: col.name,
        type: col.type.to_s,
        label: klass.human_attribute_name(col.name),
        nullable: col.null,
        default: col.default
      }
    end
  end

  def extract_associations(klass)
    klass.reflect_on_all_associations.map do |assoc|
      {
        name: assoc.name.to_s,
        macro: assoc.macro.to_s,
        target_class: assoc.class_name
      }
    end
  end
end
