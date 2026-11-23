# frozen_string_literal: true

module Websites
  # Gradient stand-in when an image URL is blank. Never renders <img src="">.
  class PlaceholderImageComponent < PublicComponent
    def initialize(appearance: "light", theme: nil, **html_options)
      @theme = theme
      @appearance = appearance.to_s == "dark" || theme&.dark? ? "dark" : "light"
      @fallback_theme = Websites::Theme.new((theme&.tokens || {}).merge("appearance" => @appearance))
      @extra_class = html_options[:class]
    end

    def css_class
      [ "bg-transparent", @extra_class ].compact.join(" ")
    end

    def gradient_class
      @fallback_theme.placeholder_class
    end

    def blob_class
      @fallback_theme.placeholder_blob_class
    end
  end
end
