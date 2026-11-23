# frozen_string_literal: true

# Generated page ERB hides a locked input's field when the controller resolved
# a server-side value for it (@page_bindings, from Pages::InputBindings).
module PageInputsHelper
  def page_input_bound?(slug) = @page_bindings.to_h.key?(slug.to_s)
end
