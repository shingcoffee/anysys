# frozen_string_literal: true

module FlowchartDefinitions
  # Creates or version-updates one customer-owned flowchart.
  class Persist
    Result = Struct.new(:created, :updated, :errors, keyword_init: true) do
      def ok? = errors.empty?
    end

    def self.call(normalized:, customer:)
      new(normalized: normalized, customer: customer).call
    end

    def initialize(normalized:, customer:)
      @normalized = normalized
      @customer = customer
    end

    def call
      return failure([I18n.t("ai_assistant.assistant.apply_errors.no_customer")]) if @customer.blank?

      Current.with_customer(@customer) { write }
    rescue Writer::Failed => e
      failure(e.messages)
    end

    private

    def write
      Writer.new(@normalized, customer: @customer).run
    end

    def failure(messages)
      Result.new(created: nil, updated: nil, errors: Array(messages))
    end

    class Writer
      class Failed < StandardError
        attr_reader :messages

        def initialize(messages)
          @messages = Array(messages)
          super(@messages.join(" "))
        end
      end

      def initialize(normalized, customer:)
        @normalized = normalized
        @customer = customer
      end

      def run
        record = find_existing
        record.nil? ? create! : update!(record)
      end

      private

      def fail!(messages)
        raise Failed, messages
      end

      def find_existing
        Flowchart.unscoped.where(customer_id: @customer.id, name: @normalized.name).first
      end

      def create!
        record = Flowchart.new(
          name: @normalized.name,
          description: @normalized.description,
          customer: @customer,
          status: :draft
        )
        assign_configuration!(record)
        validate_launch!(record)
        record.status = :launched
        save!(record)
        Result.new(created: record.name, updated: nil, errors: [])
      end

      def update!(record)
        if record.deleted?
          fail!(I18n.t("ai_assistant.assistant.apply_errors.flowchart_inactive", name: record.name))
        end
        unless record.customer_owned? && record.customer_id == @customer.id
          fail!(I18n.t("ai_assistant.assistant.apply_errors.flowchart_forbidden_identity"))
        end

        record.assistant_version_write = true
        record.commit_description = I18n.t("ai_assistant.assistant.flowchart_version_description")
        record.description = @normalized.description if @normalized.description.present?
        assign_configuration!(record)
        save!(record)
        Result.new(created: nil, updated: record.name, errors: [])
      end

      def assign_configuration!(record)
        record.configuration_json = @normalized.configuration
      end

      def validate_launch!(record)
        input_errors = FlowchartInputOutputValidator.call(record).errors
        fail!(input_errors.map { |error| error[:message] }) if input_errors.any?

        # The server validator assigns configuration and runs code generation;
        # keep its mutable graph separate from the candidate we will save.
        errors = FlowchartServerValidator.new(record.dup, record.configuration_json.deep_dup).call
                                         .select { |problem| problem[:severity] == "error" }
                                         .map { |problem| problem[:message] }
        fail!(errors) if errors.any?
      end

      def save!(record)
        return if record.save

        fail!(record.errors.full_messages.presence || I18n.t("ai_assistant.assistant.apply_errors.flowchart_save_failed"))
      end
    end
  end
end
