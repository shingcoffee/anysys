# frozen_string_literal: true

class ApplicationComponent < ViewComponent::Base
  # Visually hidden without Tailwind's sr-only clip-path, which makes overflow
  # panes grow a blank scroll region beneath the real content.
  def visually_hidden_class
    "a11y-clip absolute m-0 size-px overflow-clip whitespace-nowrap border-0 p-0 [clip:rect(0,0,0,0)]"
  end

  private

  def default_html_attributes
    {}
  end

  def merge_html_attributes(base, override)
    base = base.dup
    override = override.dup

    # Merge classes if both have them
    if base[:class] && override[:class]
      base[:class] = "#{base[:class]} #{override[:class]}"
      override.delete(:class)
    end

    # Merge data attributes if both have them
    if base[:data] && override[:data]
      base[:data] = base[:data].merge(override[:data])
      override.delete(:data)
    end

    base.merge(override)
  end
end
