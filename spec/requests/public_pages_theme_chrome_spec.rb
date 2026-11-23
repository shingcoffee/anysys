# frozen_string_literal: true

require "rails_helper"

# Request specs verifying that the public chrome (public_page layout) emits
# the correct theme-derived Tailwind class strings in the rendered HTML body.
# These cover the ThemeResolver preset-detection path end-to-end: browser hits
# the public URL, the layout calls PageChromeHelper#page_chrome_bg which invokes
# resolve_page_chrome_bg → detect_preset → PAGE_CHROME_BG_MAP.
RSpec.describe "Public page chrome rendering", type: :request do
  let_it_be(:customer) { create(:customer) }

  def build_public_page(theme: {})
    config = { "fields" => [], "metadata" => {} }
    config["theme"] = theme if theme.present?
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public,
             customer:    customer,
             launched:   true,
             public_uuid: SecureRandom.uuid,
             configuration: config.to_json)
    end
  end

  describe "showcase preset theme" do
    let(:page_rec) { build_public_page(theme: ThemeResolver::THEME_PRESETS["showcase"].dup) }

    it "renders the showcase chrome gradient (from-violet-950) in the body" do
      get "/#{customer.id}/page/#{page_rec.public_uuid}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("from-violet-950")
    end
  end

  describe "modern preset theme" do
    let(:page_rec) { build_public_page(theme: ThemeResolver::THEME_PRESETS["modern"].dup) }

    it "renders the modern chrome gradient (from-slate-50) in the body" do
      get "/#{customer.id}/page/#{page_rec.public_uuid}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("from-slate-50")
    end
  end

  describe "empty / no theme (default chrome)" do
    let(:page_rec) { build_public_page(theme: {}) }

    it "renders the indigo-tinted fallback chrome (from-slate-50) for default indigo primary color" do
      get "/#{customer.id}/page/#{page_rec.public_uuid}"
      expect(response).to have_http_status(:ok)
      # Empty theme resolves to THEME_DEFAULTS (primary_color: 'indigo'),
      # which is not a preset match → PAGE_CHROME_BG_BY_HUE['indigo'] = 'bg-gradient-to-br from-slate-50 to-indigo-50'
      expect(response.body).to include("from-slate-50")
    end
  end

  describe "customized theme with rose primary color" do
    let(:rose_theme) do
      ThemeResolver::THEME_PRESETS["modern"].merge("primary_color" => "rose")
    end
    let(:page_rec) { build_public_page(theme: rose_theme) }

    it "renders the rose hue-fallback chrome (bg-rose-50/60) in the body" do
      get "/#{customer.id}/page/#{page_rec.public_uuid}"
      expect(response).to have_http_status(:ok)
      # Customized theme (not an exact preset) → PAGE_CHROME_BG_BY_HUE['rose'] = 'bg-rose-50/60'
      expect(response.body).to include("bg-rose-50/60")
    end
  end

  describe "minimalist preset theme (bare chrome)" do
    let(:page_rec) { build_public_page(theme: ThemeResolver::THEME_PRESETS["minimalist"].dup) }

    it "renders bg-white chrome for the minimalist preset" do
      get "/#{customer.id}/page/#{page_rec.public_uuid}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("bg-white")
    end
  end

  # Task C — g. End-to-end: a published public page with one of each layout
  # element type returns HTTP 200 and the body contains semantic HTML markers
  # for each element type.
  describe "end-to-end: published public page containing all layout element types" do
    let(:all_layout_config) do
      {
        "pages" => [{
          "id"     => "page_1",
          "name"   => "All Elements",
          "fields" => [
            { "id" => "e_section",  "field_type" => "section",      "property_type" => "layout",
              "label" => "Test Section" },
            { "id" => "e_divider",  "field_type" => "divider",      "property_type" => "layout" },
            { "id" => "e_heading",  "field_type" => "heading",      "property_type" => "layout",
              "content" => "E2E Heading", "heading_level" => "h2" },
            { "id" => "e_para",     "field_type" => "paragraph",    "property_type" => "layout",
              "content" => "E2E paragraph content" },
            { "id" => "e_spacer",   "field_type" => "spacer",       "property_type" => "layout",
              "spacer_height" => "md" },
            { "id" => "e_alert",    "field_type" => "alert",        "property_type" => "layout",
              "content" => "E2E alert text", "alert_variant" => "info" },
            { "id" => "e_image",    "field_type" => "image",        "property_type" => "layout",
              "image_url" => "https://example.com/img.png", "alt_text" => "test image" },
            { "id" => "e_callout",  "field_type" => "callout",      "property_type" => "layout",
              "content" => "E2E callout content" },
            { "id" => "e_quote",    "field_type" => "quote",        "property_type" => "layout",
              "content" => "E2E quote text", "attribution" => "E2E Author" },
            { "id" => "e_button",   "field_type" => "button",       "property_type" => "layout",
              "content" => "E2E Button", "button_url" => "https://example.com" },
            { "id" => "e_video",    "field_type" => "video",        "property_type" => "layout",
              "video_url" => "https://www.youtube.com/watch?v=dQw4w9WgXcQ" },
            { "id" => "e_list",     "field_type" => "list",         "property_type" => "layout",
              "content" => "Item A\nItem B\nItem C" },
            { "id" => "e_code",     "field_type" => "code_block",   "property_type" => "layout",
              "content" => "puts 'hello'", "code_language" => "Ruby" },
            { "id" => "e_card",     "field_type" => "card",         "property_type" => "layout",
              "label" => "E2E Card Title", "content" => "E2E card body" },
            { "id" => "e_progress", "field_type" => "progress_bar", "property_type" => "layout",
              "label" => "E2E Progress", "progress_value" => 60, "progress_color" => "green" },
            { "id" => "e_columns",  "field_type" => "columns",      "property_type" => "layout",
              "column_layout" => "50-50",
              "columns" => [{ "fields" => [] }, { "fields" => [] }] }
          ]
        }],
        "fields"   => [],
        "settings" => {},
        "metadata" => {},
        "theme"    => { "primary_color" => "indigo", "accent_color" => "indigo",
                        "font_family" => "sans", "border_radius" => "lg" }
      }
    end

    let(:page_rec) do
      Current.set(customer: customer) do
        create(:page, :for_member, :for_public,
               customer:     customer,
               launched:    true,
               public_uuid: SecureRandom.uuid,
               configuration: all_layout_config.to_json)
      end
    end

    before { get "/#{customer.id}/page/#{page_rec.public_uuid}" }

    it "renders a fieldset/legend for the section element" do
      # SectionElementComponent renders <fieldset><legend>...</legend></fieldset>
      expect(response.body).to include("<fieldset")
      expect(response.body).to include("Test Section")
    end

    it "renders a blockquote for the quote element" do
      expect(response.body).to include("<blockquote")
      expect(response.body).to include("E2E quote text")
    end

    it "renders a list (ul) for the list element" do
      expect(response.body).to include("<ul")
      expect(response.body).to include("Item A")
    end

    it "renders a progress bar div with the correct width style" do
      expect(response.body).to include("width: 60%")
    end

    it "renders the heading text" do
      expect(response.body).to include("E2E Heading")
    end

    it "renders the paragraph content" do
      expect(response.body).to include("E2E paragraph content")
    end

    it "renders the alert content" do
      expect(response.body).to include("E2E alert text")
    end

    it "renders the callout content" do
      expect(response.body).to include("E2E callout content")
    end

    it "renders the card title" do
      expect(response.body).to include("E2E Card Title")
    end

    it "renders the button text" do
      expect(response.body).to include("E2E Button")
    end
  end
end
