# frozen_string_literal: true

require "rails_helper"

RSpec.describe ThemeResolver do
  # Create a test class that includes the concern
  let(:resolver) do
    Class.new do
      include ThemeResolver
      # Expose private methods for testing
      public :resolve_theme, :color_palette, :resolve_font_class, :resolve_radius_class,
             :resolve_input_classes, :resolve_form_bg, :resolve_submit_button_classes,
             :resolve_accent_palette, :resolve_form_width, :resolve_form_shadow,
             :resolve_form_padding, :resolve_form_border, :resolve_field_spacing,
             :resolve_label_classes, :resolve_button_style_classes,
             :resolve_button_width, :resolve_button_size,
             :detect_preset, :resolve_page_chrome_bg, :resolve_page_chrome_header_color,
             :resolve_page_chrome_desc_color, :resolve_page_chrome_card,
             :resolve_section_top_margin, :resolve_section_bottom_margin,
             :resolve_section_border, :resolve_section_legend_extra,
             :resolve_divider_spacing, :resolve_heading_top_margin
    end.new
  end

  describe "#resolve_theme" do
    it "returns defaults for nil theme" do
      result = resolver.resolve_theme(nil)
      expect(result).to eq(ThemeResolver::THEME_DEFAULTS)
    end

    it "returns defaults for empty theme" do
      result = resolver.resolve_theme({})
      expect(result).to eq(ThemeResolver::THEME_DEFAULTS)
    end

    it "merges custom values over defaults" do
      result = resolver.resolve_theme({ "primary_color" => "blue", "font_family" => "serif" })
      expect(result["primary_color"]).to eq("blue")
      expect(result["font_family"]).to eq("serif")
      expect(result["border_radius"]).to eq("lg") # default
    end

    it "includes all new default keys" do
      result = resolver.resolve_theme({})
      %w[accent_color form_width form_shadow form_padding form_border
         field_spacing input_size label_style button_style button_width button_size].each do |key|
        expect(result).to have_key(key), "Expected default key '#{key}' to be present"
      end
    end
  end

  describe "#color_palette" do
    it "returns the correct palette for each color" do
      ThemeResolver::COLOR_PALETTES.each_key do |color|
        palette = resolver.color_palette({ "primary_color" => color })
        expect(palette[:bg]).to include(color)
      end
    end

    it "falls back to indigo for unknown color" do
      palette = resolver.color_palette({ "primary_color" => "unknown" })
      expect(palette[:bg]).to eq("bg-indigo-600")
    end
  end

  describe "#resolve_font_class" do
    it "returns font-sans for sans" do
      expect(resolver.resolve_font_class({ "font_family" => "sans" })).to eq("font-sans")
    end

    it "returns font-serif for serif" do
      expect(resolver.resolve_font_class({ "font_family" => "serif" })).to eq("font-serif")
    end

    it "returns font-mono for mono" do
      expect(resolver.resolve_font_class({ "font_family" => "mono" })).to eq("font-mono")
    end

    it "defaults to font-sans for unknown value" do
      expect(resolver.resolve_font_class({ "font_family" => "unknown" })).to eq("font-sans")
    end
  end

  describe "#resolve_radius_class" do
    it "maps each radius option correctly" do
      expect(resolver.resolve_radius_class({ "border_radius" => "none" })).to eq("rounded-none")
      expect(resolver.resolve_radius_class({ "border_radius" => "sm" })).to eq("rounded")
      expect(resolver.resolve_radius_class({ "border_radius" => "md" })).to eq("rounded-md")
      expect(resolver.resolve_radius_class({ "border_radius" => "lg" })).to eq("rounded-lg")
      expect(resolver.resolve_radius_class({ "border_radius" => "full" })).to eq("rounded-full")
    end

    it "defaults to rounded-lg for unknown value" do
      expect(resolver.resolve_radius_class({ "border_radius" => "unknown" })).to eq("rounded-lg")
    end
  end

  describe "#resolve_input_classes" do
    it "includes outline styles by default" do
      result = resolver.resolve_input_classes({})
      expect(result).to include("border border-gray-300 bg-white")
      expect(result).to include("rounded-lg")
    end

    it "includes filled styles" do
      result = resolver.resolve_input_classes({ "input_style" => "filled" })
      expect(result).to include("border-0 bg-gray-100")
    end

    it "includes underline styles without border-radius" do
      result = resolver.resolve_input_classes({ "input_style" => "underline" })
      expect(result).to include("border-0 border-b-2 border-gray-300 bg-transparent rounded-none")
      expect(result).not_to include("rounded-lg")
    end

    it "includes ring color matching primary color" do
      result = resolver.resolve_input_classes({ "primary_color" => "rose" })
      # resolve_input_classes uses ring_color key (ring-rose-500), not the ring key (focus:ring-rose-500)
      expect(result).to include("ring-rose-500")
    end

    it "uses input_size for sizing classes" do
      result = resolver.resolve_input_classes({ "input_size" => "lg" })
      expect(result).to include("px-4 py-3 text-base")
    end

    it "uses small size classes" do
      result = resolver.resolve_input_classes({ "input_size" => "sm" })
      expect(result).to include("px-2.5 py-1.5 text-sm")
    end
  end

  describe "#resolve_form_bg" do
    it "returns bg-white for white" do
      expect(resolver.resolve_form_bg({ "form_background" => "white" })).to eq("bg-white")
    end

    it "returns bg-gray-50 for gray" do
      expect(resolver.resolve_form_bg({ "form_background" => "gray" })).to eq("bg-gray-50")
    end

    it "returns bg-amber-50/60 for warm" do
      expect(resolver.resolve_form_bg({ "form_background" => "warm" })).to eq("bg-amber-50/60")
    end

    it "defaults to bg-white for unknown value" do
      expect(resolver.resolve_form_bg({ "form_background" => "unknown" })).to eq("bg-white")
    end
  end

  describe "#resolve_accent_palette" do
    it "returns the correct accent palette" do
      palette = resolver.resolve_accent_palette({ "accent_color" => "rose" })
      expect(palette[:text]).to eq("text-rose-600")
      expect(palette[:bg]).to eq("bg-rose-100")
      expect(palette[:border]).to eq("border-rose-400")
    end

    it "defaults to indigo for unknown color" do
      palette = resolver.resolve_accent_palette({ "accent_color" => "unknown" })
      expect(palette[:text]).to eq("text-indigo-600")
    end
  end

  describe "#resolve_form_width" do
    it "maps each width option correctly" do
      expect(resolver.resolve_form_width({ "form_width" => "sm" })).to eq("max-w-md")
      expect(resolver.resolve_form_width({ "form_width" => "md" })).to eq("max-w-lg")
      expect(resolver.resolve_form_width({ "form_width" => "lg" })).to eq("max-w-2xl")
      expect(resolver.resolve_form_width({ "form_width" => "xl" })).to eq("max-w-4xl")
      expect(resolver.resolve_form_width({ "form_width" => "full" })).to eq("max-w-full")
    end

    it "defaults to max-w-4xl for unknown value" do
      expect(resolver.resolve_form_width({ "form_width" => "unknown" })).to eq("max-w-4xl")
    end
  end

  describe "#resolve_form_shadow" do
    it "maps each shadow option correctly" do
      expect(resolver.resolve_form_shadow({ "form_shadow" => "none" })).to eq("")
      expect(resolver.resolve_form_shadow({ "form_shadow" => "sm" })).to eq("shadow-sm")
      expect(resolver.resolve_form_shadow({ "form_shadow" => "md" })).to eq("shadow-md")
      expect(resolver.resolve_form_shadow({ "form_shadow" => "lg" })).to eq("shadow-lg")
      expect(resolver.resolve_form_shadow({ "form_shadow" => "xl" })).to eq("shadow-xl")
    end

    it "defaults to empty string for unknown value" do
      expect(resolver.resolve_form_shadow({ "form_shadow" => "unknown" })).to eq("")
    end
  end

  describe "#resolve_form_padding" do
    it "maps each padding option correctly" do
      expect(resolver.resolve_form_padding({ "form_padding" => "compact" })).to eq("p-4")
      expect(resolver.resolve_form_padding({ "form_padding" => "normal" })).to eq("p-6")
      expect(resolver.resolve_form_padding({ "form_padding" => "spacious" })).to eq("p-8")
      expect(resolver.resolve_form_padding({ "form_padding" => "generous" })).to eq("p-10")
    end

    it "defaults to p-6 for unknown value" do
      expect(resolver.resolve_form_padding({ "form_padding" => "unknown" })).to eq("p-6")
    end
  end

  describe "#resolve_form_border" do
    it "maps each border option correctly" do
      expect(resolver.resolve_form_border({ "form_border" => "none" })).to eq("")
      expect(resolver.resolve_form_border({ "form_border" => "subtle" })).to eq("border border-gray-100")
      expect(resolver.resolve_form_border({ "form_border" => "visible" })).to eq("border border-gray-200")
      expect(resolver.resolve_form_border({ "form_border" => "strong" })).to eq("border-2 border-gray-300")
    end

    it "defaults to empty string for unknown value" do
      expect(resolver.resolve_form_border({ "form_border" => "unknown" })).to eq("")
    end
  end

  describe "#resolve_field_spacing" do
    it "maps each spacing option correctly" do
      expect(resolver.resolve_field_spacing({ "field_spacing" => "tight" })).to eq("space-y-3")
      expect(resolver.resolve_field_spacing({ "field_spacing" => "normal" })).to eq("space-y-5")
      expect(resolver.resolve_field_spacing({ "field_spacing" => "relaxed" })).to eq("space-y-8")
    end

    it "defaults to space-y-5 for unknown value" do
      expect(resolver.resolve_field_spacing({ "field_spacing" => "unknown" })).to eq("space-y-5")
    end
  end

  describe "#resolve_label_classes" do
    it "returns default label classes" do
      result = resolver.resolve_label_classes({})
      expect(result).to include("block text-sm font-medium text-gray-700 mb-1")
    end

    it "returns bold label classes" do
      result = resolver.resolve_label_classes({ "label_style" => "bold" })
      expect(result).to include("block text-sm font-bold text-gray-900 mb-1")
    end

    it "returns uppercase label classes" do
      result = resolver.resolve_label_classes({ "label_style" => "uppercase" })
      expect(result).to include("uppercase")
      expect(result).to include("tracking-widest")
    end

    it "returns floating label classes" do
      result = resolver.resolve_label_classes({ "label_style" => "floating" })
      expect(result).to include("text-xs")
      expect(result).to include("mb-0.5")
    end

    it "defaults to default for unknown value" do
      result = resolver.resolve_label_classes({ "label_style" => "unknown" })
      expect(result).to include("block text-sm font-medium text-gray-700 mb-1")
    end
  end

  describe "#resolve_button_style_classes" do
    it "returns filled style classes" do
      result = resolver.resolve_button_style_classes({ "button_style" => "filled" })
      expect(result).to include("bg-indigo-600")
      expect(result).to include("text-white")
    end

    it "returns outline style classes" do
      result = resolver.resolve_button_style_classes({ "button_style" => "outline" })
      expect(result).to include("border-2")
      expect(result).to include("bg-transparent")
    end

    it "returns soft style classes" do
      result = resolver.resolve_button_style_classes({ "button_style" => "soft", "primary_color" => "rose" })
      expect(result).to include("bg-rose-50")
      expect(result).to include("text-rose-600")
    end

    it "returns gradient style classes" do
      result = resolver.resolve_button_style_classes({ "button_style" => "gradient" })
      expect(result).to include("bg-gradient-to-r")
      expect(result).to include("text-white")
    end

    it "defaults to filled for unknown value" do
      result = resolver.resolve_button_style_classes({ "button_style" => "unknown" })
      expect(result).to include("bg-indigo-600")
      expect(result).to include("text-white")
    end
  end

  describe "#resolve_button_width" do
    it "returns auto width" do
      expect(resolver.resolve_button_width({ "button_width" => "auto" })).to eq("w-auto px-8")
    end

    it "returns full width" do
      expect(resolver.resolve_button_width({ "button_width" => "full" })).to eq("w-full")
    end

    it "defaults to full for unknown value" do
      expect(resolver.resolve_button_width({ "button_width" => "unknown" })).to eq("w-full")
    end
  end

  describe "#resolve_button_size" do
    it "maps each size option correctly" do
      expect(resolver.resolve_button_size({ "button_size" => "sm" })).to eq("py-2 text-sm")
      expect(resolver.resolve_button_size({ "button_size" => "md" })).to eq("py-2.5 text-sm")
      expect(resolver.resolve_button_size({ "button_size" => "lg" })).to eq("py-3.5 text-base")
    end

    it "defaults to md for unknown value" do
      expect(resolver.resolve_button_size({ "button_size" => "unknown" })).to eq("py-2.5 text-sm")
    end
  end

  describe "#resolve_submit_button_classes" do
    it "includes button style, width, size, and radius" do
      result = resolver.resolve_submit_button_classes({
        "primary_color" => "blue",
        "border_radius" => "md",
        "button_style" => "filled",
        "button_width" => "full",
        "button_size" => "md"
      })
      expect(result).to include("bg-blue-600")
      expect(result).to include("rounded-md")
      expect(result).to include("w-full")
      expect(result).to include("py-2.5")
      expect(result).to include("font-medium")
      expect(result).to include("mt-6")
    end

    it "uses defaults when no theme provided" do
      result = resolver.resolve_submit_button_classes({})
      expect(result).to include("bg-indigo-600")
      expect(result).to include("rounded-lg")
      expect(result).to include("w-full")
    end

    it "supports gradient button style" do
      result = resolver.resolve_submit_button_classes({ "button_style" => "gradient" })
      expect(result).to include("bg-gradient-to-r")
    end

    it "supports auto width with padding" do
      result = resolver.resolve_submit_button_classes({ "button_width" => "auto" })
      expect(result).to include("w-auto")
      expect(result).to include("px-8")
    end

    it "supports large button size" do
      result = resolver.resolve_submit_button_classes({ "button_size" => "lg" })
      expect(result).to include("py-3.5")
      expect(result).to include("text-base")
    end
  end

  describe "THEME_PRESETS" do
    it "defines all six presets" do
      expect(ThemeResolver::THEME_PRESETS.keys).to contain_exactly("modern", "minimalist", "bold", "elegant", "playful", "showcase")
    end

    it "each preset covers all theme default keys" do
      ThemeResolver::THEME_PRESETS.each do |name, preset|
        ThemeResolver::THEME_DEFAULTS.each_key do |key|
          expect(preset).to have_key(key), "Preset '#{name}' is missing key '#{key}'"
        end
      end
    end
  end

  describe "THEME_PRESETS['showcase']" do
    subject(:preset) { ThemeResolver::THEME_PRESETS["showcase"] }

    it "exists" do
      expect(preset).to be_a(Hash)
    end

    it "uses the violet primary and accent color" do
      expect(preset["primary_color"]).to eq("violet")
      expect(preset["accent_color"]).to eq("violet")
    end

    it "uses outline input style with sans font and large radius" do
      expect(preset["input_style"]).to eq("outline")
      expect(preset["font_family"]).to eq("sans")
      expect(preset["border_radius"]).to eq("lg")
    end

    it "uses full form width with subtle border and pronounced shadow" do
      expect(preset["form_width"]).to eq("full")
      expect(preset["form_shadow"]).to eq("xl")
      expect(preset["form_border"]).to eq("subtle")
      expect(preset["form_background"]).to eq("white")
    end

    it "uses generous padding and relaxed spacing for readability" do
      expect(preset["form_padding"]).to eq("generous")
      expect(preset["field_spacing"]).to eq("relaxed")
    end

    it "uses large inputs with uppercase labels for accessibility and polish" do
      expect(preset["input_size"]).to eq("lg")
      expect(preset["label_style"]).to eq("uppercase")
    end

    it "uses a gradient full-width large CTA button" do
      expect(preset["button_style"]).to eq("gradient")
      expect(preset["button_width"]).to eq("full")
      expect(preset["button_size"]).to eq("lg")
    end

    it "uses only token values that are valid against every existing _MAP constant" do
      checks = {
        "border_radius" => ThemeResolver::RADIUS_MAP,
        "font_family"   => ThemeResolver::FONT_MAP,
        "form_background" => ThemeResolver::FORM_BG_MAP,
        "form_width"    => ThemeResolver::FORM_WIDTH_MAP,
        "form_shadow"   => ThemeResolver::FORM_SHADOW_MAP,
        "form_padding"  => ThemeResolver::FORM_PADDING_MAP,
        "form_border"   => ThemeResolver::FORM_BORDER_MAP,
        "field_spacing" => ThemeResolver::FIELD_SPACING_MAP,
        "input_size"    => ThemeResolver::INPUT_SIZE_MAP,
        "label_style"   => ThemeResolver::LABEL_STYLE_MAP,
        "button_style"  => ThemeResolver::BUTTON_STYLE_MAP,
        "button_width"  => ThemeResolver::BUTTON_WIDTH_MAP,
        "button_size"   => ThemeResolver::BUTTON_SIZE_MAP
      }
      checks.each do |token, map|
        expect(map).to have_key(preset[token]),
          "preset['#{token}'] = #{preset[token].inspect} but #{map.keys.inspect} is the valid set"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # New chrome-resolution specs (added for themed-templates redesign)
  # ---------------------------------------------------------------------------

  describe "#detect_preset" do
    it "returns the preset name when the theme is an exact match" do
      ThemeResolver::THEME_PRESETS.each do |name, preset|
        expect(resolver.detect_preset(preset.dup)).to eq(name),
          "Expected detect_preset to return '#{name}' for exact preset hash"
      end
    end

    it "returns 'modern' for the modern preset hash" do
      modern = ThemeResolver::THEME_PRESETS["modern"].dup
      expect(resolver.detect_preset(modern)).to eq("modern")
    end

    it "returns 'showcase' for the showcase preset hash" do
      showcase = ThemeResolver::THEME_PRESETS["showcase"].dup
      expect(resolver.detect_preset(showcase)).to eq("showcase")
    end

    it "returns nil for a customized theme that differs from every preset" do
      custom_theme = ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "teal")
      expect(resolver.detect_preset(custom_theme)).to be_nil
    end

    it "returns nil for an empty theme" do
      # THEME_DEFAULTS does not match any preset — presets all differ from defaults
      expect(resolver.detect_preset({})).to be_nil
    end

    it "returns nil for nil theme" do
      expect(resolver.detect_preset(nil)).to be_nil
    end
  end

  describe "#resolve_page_chrome_bg" do
    context "with an exact preset theme" do
      it "returns the preset chrome bg for 'showcase'" do
        showcase = ThemeResolver::THEME_PRESETS["showcase"].dup
        expect(resolver.resolve_page_chrome_bg(showcase))
          .to eq("bg-gradient-to-br from-violet-950 via-violet-900 to-indigo-900")
      end

      it "returns bg-white for the 'minimalist' preset" do
        minimalist = ThemeResolver::THEME_PRESETS["minimalist"].dup
        expect(resolver.resolve_page_chrome_bg(minimalist)).to eq("bg-white")
      end

      it "returns the gradient for the 'modern' preset" do
        modern = ThemeResolver::THEME_PRESETS["modern"].dup
        expect(resolver.resolve_page_chrome_bg(modern))
          .to eq("bg-gradient-to-br from-slate-50 to-indigo-50")
      end
    end

    context "with a customized (non-preset) theme" do
      it "returns a hue fallback for primary_color 'rose'" do
        custom = ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "rose")
        expect(resolver.resolve_page_chrome_bg(custom)).to eq("bg-rose-50/60")
      end

      it "returns bg-gray-50 when primary_color is unknown" do
        custom = ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "unknown_color")
        expect(resolver.resolve_page_chrome_bg(custom)).to eq("bg-gray-50")
      end
    end

    context "with empty/nil theme" do
      it "returns the indigo hue fallback for empty theme (defaults to indigo primary_color)" do
        # THEME_DEFAULTS has primary_color: 'indigo'; empty theme is not a preset match → hue fallback
        expect(resolver.resolve_page_chrome_bg({}))
          .to eq("bg-gradient-to-br from-slate-50 to-indigo-50")
      end
    end
  end

  describe "#resolve_page_chrome_card" do
    it "returns '' (empty string) for the exact minimalist preset" do
      minimalist = ThemeResolver::THEME_PRESETS["minimalist"].dup
      expect(resolver.resolve_page_chrome_card(minimalist)).to eq("")
    end

    it "returns 'rounded-xl overflow-hidden' as the default for a non-preset theme" do
      custom = ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "rose")
      expect(resolver.resolve_page_chrome_card(custom)).to eq("rounded-xl overflow-hidden")
    end

    it "returns the modern preset card style for an exact modern theme" do
      modern = ThemeResolver::THEME_PRESETS["modern"].dup
      expect(resolver.resolve_page_chrome_card(modern)).to eq("rounded-xl overflow-hidden")
    end

    it "returns the showcase card style for an exact showcase theme" do
      showcase = ThemeResolver::THEME_PRESETS["showcase"].dup
      expect(resolver.resolve_page_chrome_card(showcase)).to eq("rounded-2xl overflow-hidden shadow-2xl")
    end
  end

  # Task C — ELEMENT_NEUTRALS contract
  describe "ELEMENT_NEUTRALS" do
    subject(:neutrals) { ThemeResolver::ELEMENT_NEUTRALS }

    it "is a frozen hash" do
      expect(neutrals).to be_frozen
    end

    it "defines all nine expected keys" do
      expected_keys = %i[muted_text faint_text body_text strong_text subtle_border
                         soft_border surface surface_muted track]
      expect(neutrals.keys).to match_array(expected_keys)
    end

    it "maps muted_text to text-gray-500" do
      expect(neutrals[:muted_text]).to eq("text-gray-500")
    end

    it "maps faint_text to text-gray-400" do
      expect(neutrals[:faint_text]).to eq("text-gray-400")
    end

    it "maps body_text to text-gray-600" do
      expect(neutrals[:body_text]).to eq("text-gray-600")
    end

    it "maps strong_text to text-gray-900" do
      expect(neutrals[:strong_text]).to eq("text-gray-900")
    end

    it "maps subtle_border to border-gray-100" do
      expect(neutrals[:subtle_border]).to eq("border-gray-100")
    end

    it "maps soft_border to border-gray-200" do
      expect(neutrals[:soft_border]).to eq("border-gray-200")
    end

    it "maps surface to bg-white" do
      expect(neutrals[:surface]).to eq("bg-white")
    end

    it "maps surface_muted to bg-gray-50" do
      expect(neutrals[:surface_muted]).to eq("bg-gray-50")
    end

    it "maps track to bg-gray-100" do
      expect(neutrals[:track]).to eq("bg-gray-100")
    end

    it "raises KeyError for an unknown key (fetch contract)" do
      expect { neutrals.fetch(:nonexistent_key) }.to raise_error(KeyError)
    end
  end

  describe "#resolve_page_chrome_header_color" do
    it "returns 'text-white' for the showcase preset" do
      showcase = ThemeResolver::THEME_PRESETS["showcase"].dup
      expect(resolver.resolve_page_chrome_header_color(showcase)).to eq("text-white")
    end

    it "returns 'text-gray-900' for the modern preset" do
      modern = ThemeResolver::THEME_PRESETS["modern"].dup
      expect(resolver.resolve_page_chrome_header_color(modern)).to eq("text-gray-900")
    end

    it "returns 'text-gray-900' (default) when no preset is detected" do
      custom = ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "rose")
      expect(resolver.resolve_page_chrome_header_color(custom)).to eq("text-gray-900")
    end
  end

  # ---------------------------------------------------------------------------
  # v2 spacing rhythm — new maps and resolver methods
  # ---------------------------------------------------------------------------

  describe "SECTION_SPACING_MAP" do
    it "is frozen" do
      expect(ThemeResolver::SECTION_SPACING_MAP).to be_frozen
    end

    it "defines tight, normal, and relaxed keys" do
      expect(ThemeResolver::SECTION_SPACING_MAP.keys).to contain_exactly("tight", "normal", "relaxed")
    end

    it "provides :mt and :mb for each spacing key" do
      ThemeResolver::SECTION_SPACING_MAP.each do |key, val|
        expect(val).to have_key(:mt), "SECTION_SPACING_MAP[#{key.inspect}] is missing :mt"
        expect(val).to have_key(:mb), "SECTION_SPACING_MAP[#{key.inspect}] is missing :mb"
      end
    end
  end

  describe "DIVIDER_SPACING_MAP" do
    it "is frozen" do
      expect(ThemeResolver::DIVIDER_SPACING_MAP).to be_frozen
    end

    it "returns my-3 for tight, my-5 for normal, my-6 for relaxed" do
      expect(ThemeResolver::DIVIDER_SPACING_MAP["tight"]).to eq("my-3")
      expect(ThemeResolver::DIVIDER_SPACING_MAP["normal"]).to eq("my-5")
      expect(ThemeResolver::DIVIDER_SPACING_MAP["relaxed"]).to eq("my-6")
    end
  end

  describe "SECTION_BORDER_MAP" do
    it "is frozen" do
      expect(ThemeResolver::SECTION_BORDER_MAP).to be_frozen
    end

    it "returns a left-border accent for modern preset" do
      expect(ThemeResolver::SECTION_BORDER_MAP["modern"]).to include("border-l-2")
      expect(ThemeResolver::SECTION_BORDER_MAP["modern"]).to include("border-indigo-300")
    end

    it "returns empty string for minimalist and elegant" do
      expect(ThemeResolver::SECTION_BORDER_MAP["minimalist"]).to eq("")
      expect(ThemeResolver::SECTION_BORDER_MAP["elegant"]).to eq("")
    end
  end

  describe "SECTION_LEGEND_EXTRA_MAP" do
    it "is frozen" do
      expect(ThemeResolver::SECTION_LEGEND_EXTRA_MAP).to be_frozen
    end

    it "returns uppercase classes for minimalist and showcase" do
      expect(ThemeResolver::SECTION_LEGEND_EXTRA_MAP["minimalist"]).to include("uppercase")
      expect(ThemeResolver::SECTION_LEGEND_EXTRA_MAP["showcase"]).to include("uppercase")
    end

    it "returns font-bold for bold preset" do
      expect(ThemeResolver::SECTION_LEGEND_EXTRA_MAP["bold"]).to include("font-bold")
    end

    it "returns serif/violet classes for elegant" do
      expect(ThemeResolver::SECTION_LEGEND_EXTRA_MAP["elegant"]).to include("font-serif")
      expect(ThemeResolver::SECTION_LEGEND_EXTRA_MAP["elegant"]).to include("text-violet-900")
    end
  end

  describe "#resolve_section_top_margin" do
    it "returns mt-6 for tight spacing" do
      expect(resolver.resolve_section_top_margin({ "field_spacing" => "tight" })).to eq("mt-6")
    end

    it "returns mt-6 for normal spacing" do
      expect(resolver.resolve_section_top_margin({ "field_spacing" => "normal" })).to eq("mt-6")
    end

    it "returns mt-8 for relaxed spacing" do
      expect(resolver.resolve_section_top_margin({ "field_spacing" => "relaxed" })).to eq("mt-8")
    end

    it "defaults to mt-6 for unknown spacing" do
      expect(resolver.resolve_section_top_margin({})).to eq("mt-6")
    end
  end

  describe "#resolve_section_bottom_margin" do
    it "returns mb-2 for tight spacing" do
      expect(resolver.resolve_section_bottom_margin({ "field_spacing" => "tight" })).to eq("mb-2")
    end

    it "returns mb-2.5 for normal spacing" do
      expect(resolver.resolve_section_bottom_margin({ "field_spacing" => "normal" })).to eq("mb-2.5")
    end

    it "returns mb-3 for relaxed spacing" do
      expect(resolver.resolve_section_bottom_margin({ "field_spacing" => "relaxed" })).to eq("mb-3")
    end
  end

  describe "#resolve_section_border" do
    it "returns the border classes for the modern preset" do
      modern = ThemeResolver::THEME_PRESETS["modern"].dup
      result = resolver.resolve_section_border(modern)
      expect(result).to include("border-l-2")
      expect(result).to include("border-indigo-300")
    end

    it "returns empty string for minimalist preset" do
      minimalist = ThemeResolver::THEME_PRESETS["minimalist"].dup
      expect(resolver.resolve_section_border(minimalist)).to eq("")
    end

    it "returns empty string for a non-preset theme" do
      custom = ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "teal")
      expect(resolver.resolve_section_border(custom)).to eq("")
    end

    it "returns empty string for nil theme" do
      expect(resolver.resolve_section_border(nil)).to eq("")
    end
  end

  describe "#resolve_section_legend_extra" do
    it "returns uppercase classes for the minimalist preset" do
      minimalist = ThemeResolver::THEME_PRESETS["minimalist"].dup
      result = resolver.resolve_section_legend_extra(minimalist)
      expect(result).to include("uppercase")
      expect(result).to include("tracking-widest")
    end

    it "returns font-bold for the bold preset" do
      bold = ThemeResolver::THEME_PRESETS["bold"].dup
      expect(resolver.resolve_section_legend_extra(bold)).to eq("font-bold")
    end

    it "returns empty string for a non-preset theme" do
      custom = ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "teal")
      expect(resolver.resolve_section_legend_extra(custom)).to eq("")
    end
  end

  describe "#resolve_divider_spacing" do
    it "returns my-3 for tight spacing" do
      expect(resolver.resolve_divider_spacing({ "field_spacing" => "tight" })).to eq("my-3")
    end

    it "returns my-5 for normal spacing" do
      expect(resolver.resolve_divider_spacing({ "field_spacing" => "normal" })).to eq("my-5")
    end

    it "returns my-6 for relaxed spacing" do
      expect(resolver.resolve_divider_spacing({ "field_spacing" => "relaxed" })).to eq("my-6")
    end

    it "defaults to my-5 for unknown spacing" do
      expect(resolver.resolve_divider_spacing({})).to eq("my-5")
    end
  end

  describe "#resolve_heading_top_margin" do
    it "returns mt-2 for tight spacing" do
      expect(resolver.resolve_heading_top_margin({ "field_spacing" => "tight" })).to eq("mt-2")
    end

    it "returns mt-3 for normal spacing" do
      expect(resolver.resolve_heading_top_margin({ "field_spacing" => "normal" })).to eq("mt-3")
    end

    it "returns mt-4 for relaxed spacing" do
      expect(resolver.resolve_heading_top_margin({ "field_spacing" => "relaxed" })).to eq("mt-4")
    end

    it "defaults to mt-3 for unknown spacing" do
      expect(resolver.resolve_heading_top_margin({})).to eq("mt-3")
    end
  end
end
