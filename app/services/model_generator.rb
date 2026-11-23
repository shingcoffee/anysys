# frozen_string_literal: true

# ModelGenerator
#
# Generates code that dynamically configures EntityEntry for an Entity
# using Ruby metaprogramming (class_eval + attribute_accessor).
#
# No new class is defined -- EntityEntry itself is extended with typed
# accessors derived from the entity's property_schema.
#
# Following Trailblazer conventions, the model is kept thin with only
# attribute definitions - business logic belongs in Operations/Activities.
#
# @example
#   ModelGenerator.new(entity).generate
#   # => "# frozen_string_literal: true\n\nEntityEntry.class_eval do\n  ..."
#
class ModelGenerator
  # Maps HTML input types to Rails attribute types
  HTML_TYPE_MAP = {
    "text"           => :string,
    "textarea"       => :string,
    "search"         => :string,
    "password"       => :string,
    "hidden"         => :string,
    "email"          => :string,
    "tel"            => :string,
    "url"            => :string,
    "color"          => :string,
    "number"         => :integer,
    "range"          => :integer,
    "checkbox"       => :boolean,
    "select"         => :string,
    "radio"          => :string,
    "date"           => :date,
    "time"           => :time,
    "datetime-local" => :datetime,
    "month"          => :string,
    "week"           => :string,
    "file"           => :string,
    "image"          => :string
  }.freeze

  attr_reader :entity, :attributes

  def initialize(entity)
    @entity = entity
    @attributes = entity.property_schema_json || []
  end

  def generate
    return nil if entity.name.blank? || attributes.empty?

    [header, class_eval_block].join("\n")
  end

  private

  def header
    <<~RUBY.chomp
      # frozen_string_literal: true
      #
      # EntityEntry configuration for: #{entity.name}
      # Dynamically extends EntityEntry with typed attribute accessors
      #
      # == Data Attributes (stored in JSON `data` column)
      #
      #{schema_info}
    RUBY
  end

  def class_eval_block
    <<~RUBY

      EntityEntry.class_eval do
      #{attribute_declarations.indent(2)}
      end
    RUBY
  end

  def schema_info
    max_len = attributes.map { |a| a["name_slug"].length }.max || 0
    attributes.map { |attr|
      "# #{attr['name_slug'].ljust(max_len)}  :#{rails_type(attr['html_type'])}"
    }.join("\n")
  end

  def attribute_declarations
    attributes.map { |attr|
      "attribute_accessor :#{attr['name_slug']}, :#{rails_type(attr['html_type'])}"
    }.join("\n")
  end

  def rails_type(html_type)
    HTML_TYPE_MAP[html_type.to_s] || :string
  end
end
