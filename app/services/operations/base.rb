# frozen_string_literal: true

module Operations
  class Base
    KEY_FORMAT = /\A[a-z][a-z0-9_]{2,63}\z/

    class << self
      def key(value = nil)
        if value
          unless value.to_s.match?(KEY_FORMAT)
            raise ArgumentError, "operation key #{value.inspect} must match #{KEY_FORMAT}"
          end

          @key = value.to_s
        end
        inherited_setting(:@key)
      end

      def version(value = nil)
        @version = value if value
        inherited_setting(:@version) || 1
      end

      def title(value = nil)
        @title = value if value
        inherited_setting(:@title)
      end

      def summary(value = nil)
        @summary = value if value
        inherited_setting(:@summary)
      end

      def schema(file = nil)
        @schema_file = file if file
        inherited_setting(:@schema_file)
      end

      def shared_defs(*files)
        @shared_defs = files.map(&:to_s) if files.any?
        inherited_setting(:@shared_defs) || []
      end

      def vocabulary(mod = nil)
        @vocabulary = mod if mod
        inherited_setting(:@vocabulary)
      end

      # Operations whose input carries merge patches turn this off: a default
      # inserted into a patch reads as an instruction to overwrite the stored
      # value.
      def insert_defaults(value)
        @insert_defaults = value
      end

      def insert_defaults?
        value = inherited_setting(:@insert_defaults)
        value.nil? || value
      end

      def schema_root(path = nil)
        @schema_root = Pathname(path) if path
        inherited_setting(:@schema_root) || Operations::Schema.schema_root
      end

      def annotations(read_only: false, destructive: false, idempotent: false, confirmation: :never)
        @read_only = read_only
        @destructive = destructive
        @idempotent = idempotent
        @confirmation = confirmation.to_sym
      end

      def read_only?
        !!inherited_setting(:@read_only)
      end

      def destructive?
        !!inherited_setting(:@destructive)
      end

      def idempotent?
        !!inherited_setting(:@idempotent)
      end

      def confirmation
        inherited_setting(:@confirmation) || :never
      end

      def inherited_setting(ivar)
        klass = self
        while klass && klass <= Operations::Base
          return klass.instance_variable_get(ivar) if klass.instance_variable_defined?(ivar)

          klass = klass.superclass
        end
        nil
      end
      private :inherited_setting

      def register!
        Operations.register(self)
      end

      def available?(_context)
        true
      end

      def input_schema(context)
        Schema.new(self, context: context)
      end

      def tool_definition(context)
        {
          name: key,
          description: summary,
          parameters: SchemaProjection.call(input_schema(context).document)
        }
      end
    end

    attr_reader :context

    def initialize(context:)
      @context = context
    end

    def validate(_input)
      []
    end

    def plan(_input)
      nil
    end

    def snapshot(_input)
      nil
    end

    def stale?(_snapshot)
      false
    end

    def perform(_input)
      raise NotImplementedError, "#{self.class}#perform must return an Operations::Outcome"
    end
  end
end
