# frozen_string_literal: true

module Member
  # Descriptor for a read-only member surface (index + detail).
  # Modules ship one of these as FeatureModules::<Name>::MemberSurface.
  Surface = Struct.new(:key, :label, :icon, :enabled_for, :index, :detail, :default_position, :groups,
                       :default_enabled, keyword_init: true)

  class Surface
    KEY_RE = /\A[a-z][a-z0-9_]*\z/.freeze
    DEFAULT_POSITION = 100

    def default_enabled?
      default_enabled != false
    end

    Index = Struct.new(:title, :subtitle, :scope, :columns, :empty_state, :per_page,
                       keyword_init: true) do
      def per_page_or_default
        per_page.presence || 20
      end
    end

    Detail = Struct.new(:title, :subtitle, :meta, :sections, keyword_init: true)

    def enabled_for?(user) = enabled_for.call(user)

    def default_position_or_default
      default_position.presence || DEFAULT_POSITION
    end

    def validate!
      raise ArgumentError, "key must be a lowercase identifier (got: #{key.inspect})" unless key.to_s.match?(KEY_RE)
      raise ArgumentError, "label is required"  if label.to_s.strip.empty?
      raise ArgumentError, "index must be a Member::Surface::Index"  unless index.is_a?(Index)
      raise ArgumentError, "detail must be a Member::Surface::Detail" unless detail.is_a?(Detail)

      validate_index!(index)
      validate_detail!(detail)
      true
    end

    private

    def validate_index!(idx)
      raise ArgumentError, "index.columns must be a non-empty array" if Array(idx.columns).empty?

      idx.columns.each_with_index do |col, i|
        raise ArgumentError, "index.column[#{i}] missing :key"   if col[:key].to_s.empty?
        raise ArgumentError, "index.column[#{i}] missing :label" if col[:label].to_s.empty?
        raise ArgumentError, "index.column[#{i}] missing :value (must be a callable)" unless col[:value].respond_to?(:call)
      end
    end

    def validate_detail!(det)
      Array(det.sections).each_with_index do |section, i|
        raise ArgumentError, "detail.section[#{i}] missing :key" if section[:key].to_s.empty?

        Array(section[:rows]).each_with_index do |row, j|
          raise ArgumentError, "detail.section[#{i}].row[#{j}] missing :key"   if row[:key].to_s.empty?
          raise ArgumentError, "detail.section[#{i}].row[#{j}] missing :label" if row[:label].to_s.empty?
          raise ArgumentError, "detail.section[#{i}].row[#{j}] missing :value" unless row[:value].respond_to?(:call)
        end
      end
    end
  end
end
