# frozen_string_literal: true

module AiAssistant
  module Activities
    # Updates one provider's AiAssistant::ProviderSettings row. The form posts a
    # flat params hash; vendor-specific keys are funneled into the JSON `config`
    # blob.
    #
    # Platform job assignment is a pair of *assignee* provider keys from the
    # settings UI, or per-row transcribe_active / generation_active flags.
    # Both paths go through activate_for! / deactivate_for! so at most one
    # provider holds each job. A blank api_key
    # keeps the existing encrypted value; a blank non-secret config field
    # clears it back to the provider default.
    class UpdateProviderSettings
      Result = Struct.new(:success?, :model, :errors, keyword_init: true)
      ASSIGNEE_PARAMS = { transcribe: :transcribe_assignee, generation: :generation_assignee }.freeze

      def self.call(provider:, params:)
        settings = AiAssistant::ProviderSettings.for_provider(provider)
        attrs, jobs, assignees = sanitize(params, settings)

        if jobs_only?(params, settings, assignees)
          return persist_jobs_only(settings, assignees)
        end

        settings.assign_attributes(attrs.merge(jobs_for_validation(settings, jobs, assignees)))
        assignee_errors = validate_assignees(assignees, settings)

        contract = AiAssistant::Contracts::ProviderSettings.new(settings)
        if assignee_errors.empty? && contract.validate({}) && settings.valid?
          persist!(settings, jobs, assignees)
          enqueue_cursor_health_check(settings)
          Result.new(success?: true, model: settings, errors: [])
        else
          errors = assignee_errors + contract.errors.full_messages + settings.errors.full_messages
          Result.new(success?: false, model: settings, errors: errors.uniq)
        end
      end

      def self.jobs_only?(params, settings, assignees)
        return false if assignees.empty?

        h = params.to_h.symbolize_keys
        return false if h.key?(:api_key)

        provider_class = AiAssistant::Providers.for(settings.provider)
        provider_class.config_fields.none? { |field| h.key?(field[:name].to_sym) }
      end

      def self.persist_jobs_only(settings, assignees)
        errors = validate_assignees(assignees, settings)
        if errors.any?
          return Result.new(success?: false, model: settings, errors: errors)
        end

        AiAssistant::ProviderSettings.transaction do
          apply_assignee!(:transcribe, assignees[:transcribe]) if assignees.key?(:transcribe)
          apply_assignee!(:generation, assignees[:generation]) if assignees.key?(:generation)
        end
        Result.new(success?: true, model: settings.reload, errors: [])
      end

      def self.persist!(settings, jobs, assignees)
        AiAssistant::ProviderSettings.transaction do
          settings.restore_attributes(%w[transcribe_active generation_active])
          settings.save!
          if assignees.any?
            apply_assignee!(:transcribe, assignees[:transcribe]) if assignees.key?(:transcribe)
            apply_assignee!(:generation, assignees[:generation]) if assignees.key?(:generation)
          else
            apply_job!(settings, :transcribe, jobs[:transcribe_active])
            apply_job!(settings, :generation, jobs[:generation_active])
          end
        end
      end

      def self.apply_job!(settings, job, active)
        active ? settings.activate_for!(job) : settings.deactivate_for!(job)
      end

      def self.apply_assignee!(job, key)
        if key.to_s.blank?
          holder = AiAssistant::ProviderSettings.where(AiAssistant::ProviderSettings.job_column(job) => true).first
          holder&.deactivate_for!(job)
        else
          AiAssistant::ProviderSettings.for_provider(key).activate_for!(job)
        end
      end

      def self.enqueue_cursor_health_check(settings)
        return unless settings.provider == "cursor"

        AiAssistant::TestConnectionJob.perform_later(settings.id)
      end

      def self.sanitize(params, settings)
        h = params.to_h.symbolize_keys
        attrs = {}

        if h.key?(:api_key)
          attrs[:api_key] = h[:api_key].presence || settings.api_key
        end

        attrs[:config] = merged_config(h, settings).to_json

        jobs = {
          transcribe_active: cast_flag(h, :transcribe_active, settings.transcribe_active?),
          generation_active: cast_flag(h, :generation_active, settings.generation_active?)
        }
        [ attrs, jobs, extract_assignees(h) ]
      end

      def self.extract_assignees(h)
        ASSIGNEE_PARAMS.each_with_object({}) do |(job, param), acc|
          acc[job] = h[param].to_s if h.key?(param)
        end
      end

      def self.jobs_for_validation(settings, jobs, assignees)
        result = jobs.dup
        if assignees.key?(:transcribe)
          result[:transcribe_active] = assignees[:transcribe].to_s == settings.provider.to_s
        end
        if assignees.key?(:generation)
          result[:generation_active] = assignees[:generation].to_s == settings.provider.to_s
        end
        result
      end

      def self.validate_assignees(assignees, current_settings = nil)
        assignees.each_with_object([]) do |(job, key), errors|
          next if key.blank?

          provider_class = AiAssistant::Providers.for(key)
          supported =
            if job == :transcribe
              !provider_class.respond_to?(:supports_transcribe?) || provider_class.supports_transcribe?
            else
              provider_class.respond_to?(:supports_generation?) && provider_class.supports_generation?
            end
          unless supported
            errors << I18n.t("ai_assistant.platform_settings.errors.#{job}_unsupported")
            next
          end
          unless assignee_configured?(key, current_settings)
            errors << I18n.t("ai_assistant.platform_settings.errors.unconfigured_assignee")
          end
        rescue ArgumentError
          errors << I18n.t("ai_assistant.platform_settings.errors.unknown_provider")
        end
      end

      def self.assignee_configured?(key, current_settings)
        row = if current_settings && key.to_s == current_settings.provider.to_s
          current_settings
        else
          AiAssistant::ProviderSettings.find_by(provider: key.to_s)
        end
        row&.configured?
      end

      def self.cast_flag(h, key, current)
        h.key?(key) ? ActiveModel::Type::Boolean.new.cast(h[key]) : current
      end

      # A submitted-but-blank config field clears the stored value so the
      # provider default applies again; a field the form did not submit is left
      # untouched. Secrets never travel through here — `api_key` is the only
      # encrypted attribute and #sanitize keeps its existing value when blank.
      def self.merged_config(h, settings)
        provider_class = AiAssistant::Providers.for(settings.provider)
        config = settings.config_json.dup
        provider_class.config_fields.each do |field|
          key = field[:name].to_sym
          next unless h.key?(key)

          value = h[key].to_s
          if value.strip.empty?
            config.delete(field[:name].to_s)
          else
            config[field[:name].to_s] = value
          end
        end
        config
      end
    end
  end
end
