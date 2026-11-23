# frozen_string_literal: true

# Generated page ERB calls these for the errors a refused submission left on
# a field. PageRendering sets @page_field_errors ({ slug => [message] }).
module PageFieldErrorsHelper
  def page_field_errors(slug)
    Array(@page_field_errors.to_h[slug.to_s])
  end

  def page_field_error(slug)
    render Pages::FieldErrorComponent.new(messages: page_field_errors(slug))
  end
end
