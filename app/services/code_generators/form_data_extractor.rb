# frozen_string_literal: true

module CodeGenerators
  # Form data for the new-generator form and for re-rendering a rejected save.
  # All methods are pure (no HTTP / controller context).
  class FormDataExtractor
    DEFAULT_VERSION = "1.0.0"

    def initialize(params = {})
      @params = params
    end

    # Build default form data for the "new" action.
    def default_form_data
      {
        description:      "",
        category:         @params[:category].presence || "uncategorized",
        version:          DEFAULT_VERSION,
        registered_names: "",
        methods_body:     default_methods_body
      }
    end

    # Build form data from raw request params (used after a failed create/update).
    def form_data_from_params
      {
        description:      @params[:description],
        category:         @params[:category],
        version:          @params[:version],
        registered_names: @params[:registered_names],
        methods_body:     @params[:methods_body]
      }
    end

    private

    def default_methods_body
      <<~RUBY.chomp
        config_schema do
          input :sourceVariable, required: true, example: "value"
          output :resultVar, default: "result"
        end

        def generate_body
          body(
            assign(:resultVar, read(:sourceVariable)),
            "true"
          )
        end
      RUBY
    end
  end
end
