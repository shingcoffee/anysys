# frozen_string_literal: true

# Generated page ERB calls this for an input field's initial value. Controllers
# that render a page set @page_prefill from Pages::Prefill.values (or, editing
# an entry, Pages::EntryPrefill.values). +default+ applies only to a field the
# prefill has no key for.
module PagePrefillHelper
  def page_prefill_value(slug, default: nil)
    key = slug.to_s
    @page_prefill&.key?(key) ? @page_prefill[key] : default
  end
end
