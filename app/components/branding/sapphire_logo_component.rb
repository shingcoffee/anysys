# frozen_string_literal: true

module Branding
  # Sapphire brand mark — the original faceted gem geometry, stood upright and
  # recolored in the violet family used by the public site's primary actions.
  # Shape only, no wordmark. Keep the source paths unchanged when retinting.
  #
  #   <%= render Branding::SapphireLogoComponent.new(size: :sm) %>
  #
  # size : :xs..:xl (Tailwind height) or any Tailwind height class string.
  # decorative: true hides the mark from the accessibility tree when visible
  # text already names the brand (platform marketing header and footer).
  class SapphireLogoComponent < ViewComponent::Base
    SIZES = { xs: "h-6", sm: "h-8", md: "h-12", lg: "h-16", xl: "h-24" }.freeze
    FACET_COLORS = {
      "#072a7a" => "#3b147a", "#08276e" => "#321268",
      "#0a2f86" => "#4c1d95", "#0f44b5" => "#6d28d9",
      "#1a4fc2" => "#7f22fe", "#1e5ad2" => "#8b5cf6",
      "#2a66de" => "#a78bfa", "#316fe6" => "#9f67f4",
      "#b0cdf7" => "#ede9fe"
    }.freeze
    # Tight crop of the artwork after the gem is stood upright (its table→culet
    # symmetry axis rotated to vertical).
    VIEWBOX = "-99.28 24.33 695.48 575.82"

    def initialize(size: :md, css_class: nil, title: nil, decorative: false)
      @height     = SIZES.fetch(size.to_sym, size.to_s)
      @css        = css_class
      @title      = title
      @decorative = decorative
      @uid        = SecureRandom.hex(4)
    end

    def call
      tag.svg(mark.html_safe, **svg_attributes)
    end

    private

    def svg_attributes
      attrs = {
        xmlns: "http://www.w3.org/2000/svg",
        "xmlns:xlink": "http://www.w3.org/1999/xlink",
        viewBox: VIEWBOX,
        class: ["inline-block w-auto", @height, @css].compact.join(" ")
      }
      if @decorative
        attrs[:aria] = { hidden: true }
        attrs[:focusable] = "false"
      else
        attrs[:role] = "img"
        attrs[:"aria-label"] = @title || I18n.t("chrome.topbar.brand_name")
      end
      attrs
    end

    # Per-instance gradient ids so multiple logos on one page never collide.
    def mark = MARK.gsub("-U", "-#{@uid}").gsub(/#[0-9a-f]{6}/, FACET_COLORS)

    MARK = <<~'SVG'.strip.freeze
      <defs><linearGradient id="grad1-U" x1="491.84" x2="355.9" y1="112.59" y2="203.82" gradientTransform="matrix(1 0 0 -1 0 500.11)" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#08276e"/><stop offset="0" stop-color="#08276e"/><stop offset=".99" stop-color="#0a2f86"/><stop offset="1" stop-color="#0a2f86"/></linearGradient><linearGradient xlink:href="#grad1-U" id="grad2-U" x1="383.07" x2="247.13" y1="-49.49" y2="41.73"/><linearGradient id="grad3-U" x1="450.53" x2="346.82" y1="208.6" y2="301.54" gradientTransform="matrix(1 0 0 -1 0 500.11)" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#072a7a"/><stop offset="0" stop-color="#072a7a"/><stop offset=".99" stop-color="#0f44b5"/><stop offset="1" stop-color="#0f44b5"/></linearGradient></defs><g transform="rotate(45 238.449 251.856)"><path id="polygon3282" d="M387.37 329.1 101.9 498.61l369.63-25.08L500 100.82z" fill="#2a66de" fill-rule="evenodd"/><path id="polygon3293" d="M472.14 473.28 440.37 254l-86.54 114.27z" style="fill-rule:evenodd;fill:url(#grad1-U)"/><path id="polygon3304" d="M472.57 473.28 239.82 455l-136.68 43.14z" style="fill-rule:evenodd;fill:url(#grad2-U)"/><path id="polygon3319" d="m103.47 498.18 58.14-190.48-127.95 27.36z" fill="#316fe6" fill-rule="evenodd"/><path id="polygon3334" d="m353.81 368.9-53.5-209.56L147.2 302.86z" fill="#316fe6" fill-rule="evenodd"/><path id="polygon3349" d="M487.86 162.29 343.13 44.09l-40.3 130.29z" fill="#316fe6" fill-rule="evenodd"/><path id="polygon3362" d="m420.18 1.94-85.12 47.04-53.7-47.67z" fill="#316fe6" fill-rule="evenodd"/><path id="polygon3375" d="m0 398.96 35.66-65.04-28.85-77.47z" fill="#316fe6" fill-rule="evenodd"/><path id="path3377" d="m4.9 254 29.02 82.32 126.1-28.29 143.97-133.8 40.63-129.05L280.65 0 171.88 40.71c-34.27 31.87-100.76 94.94-103.16 96.12C66.35 138.04 24.81 216.55 4.9 254" style="fill-rule:evenodd;fill:#b0cdf7"/><path id="path3400" d="M106.8 106.12c74.27-73.64 170.01-117.15 206.76-80.08 36.72 37.07-2.22 127.16-76.49 200.78-74.27 73.61-168.83 119.52-205.55 82.45-36.74-37.05 1.01-129.54 75.28-203.15" fill="#2a66de" fill-rule="evenodd"/><path id="path3413" d="m103.47 498.11 57.69-191.09 191.59 61.55c-69.27 64.96-146.32 119.87-249.28 129.54" fill="#1a4fc2" fill-rule="evenodd"/><path id="path3424" d="m304.24 173.85 49.18 194.82c57.87-60.84 109.8-126.26 135.24-207.16z" style="fill-rule:evenodd;fill:url(#grad3-U)"/><path id="path3435" d="M488.16 162.49c19.68-59.41 24.23-144.63-68.59-160.45l-76.16 42.07 144.76 118.38Z" fill="#1a4fc2" fill-rule="evenodd"/><path id="path3437" d="M0 398.1c2.73 98.04 73.46 99.51 103.59 100.37l-69.6-162.55z" fill="#1a4fc2" fill-rule="evenodd"/><path id="path3448" d="M304.52 174.15c44.47 27.33 134.08 82.22 135.9 83.23 2.82 1.59 38.64-60.39 46.76-95.42z" fill="#1e5ad2" fill-rule="evenodd"/><path id="path3459" d="m161.08 307.02 77.12 148.79c45.6-24.73 81.31-54.86 114.02-87.14z" fill="#1e5ad2" fill-rule="evenodd"/><path id="path3472" d="M33.69 336.12 22.76 466.24c20.62 28.16 48.98 30.61 78.74 28.42-21.53-53.58-64.53-160.7-67.81-158.53Z" fill="#1e5ad2" fill-rule="evenodd"/><path id="path3485" d="m342.96 44.44 153.21 21.5c-8.18-34.65-33.29-57.01-76.09-64z" fill="#1e5ad2" fill-rule="evenodd"/></g>
    SVG
  end
end
