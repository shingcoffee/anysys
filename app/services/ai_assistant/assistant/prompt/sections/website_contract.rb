# frozen_string_literal: true

module AiAssistant
  module Assistant
    module Prompt
      module Sections
        # The `apply_website` reply shape. The limits are read from the
        # extraction, and the example is checked against {Websites::SectionKit}
        # and {Websites::SectionFields} by the section spec, so neither can
        # drift from what the server accepts.
        class WebsiteContract < Section
          heads "Website output contract"
          document "website_contract"

          EXAMPLE = {
            "intent" => "apply_website",
            "reply" => "Drafted Home and Menu for Juniper Bakery: your storefront photo opens Home and the pastry shots fill the menu cards.",
            "pages" => [
              {
                "title" => "Home",
                "sections" => [
                  { "type" => "hero_cinematic",
                    "props" => { "kicker" => "Neighbourhood bakery", "headline" => "Bread worth the early start",
                                 "subhead" => "Sourdough, pastries and coffee, baked here every morning.",
                                 "primary_label" => "See the menu", "primary_href" => "menu",
                                 "image_url" => "upload:101", "tone" => "dark" } },
                  { "type" => "split_image_text",
                    "props" => { "heading" => "Baked before sunrise",
                                 "body" => "Our bakers start at four so the first loaves are still warm when the doors open.",
                                 "image_url" => "upload:102", "image_side" => "right" } },
                  { "type" => "contact_info",
                    "props" => { "heading" => "Visit us", "address" => "[Your street address]",
                                 "phone" => "[Your phone number]", "hours" => "[Opening hours]" } }
                ]
              },
              {
                "title" => "Menu",
                "slug" => "menu",
                "sections" => [
                  { "type" => "card_grid",
                    "props" => { "heading" => "From the oven",
                                 "cards" => [
                                   { "title" => "Butter croissant", "body" => "Laminated over three days.", "image_url" => "upload:103" },
                                   { "title" => "Country sourdough", "body" => "Long-fermented, dark crust.", "image_url" => "upload:104" }
                                 ] } },
                  { "type" => "price_list",
                    "props" => { "heading" => "Coffee",
                                 "items" => [{ "title" => "Flat white", "price" => "[Price]" }] } }
                ]
              }
            ]
          }.freeze

          private

          def body
            return nil unless context.website_enabled?

            [document, limits, example].join("\n\n")
          end

          def limits
            "Limits: at most #{extraction::MAX_PAGES} pages per reply and #{extraction::MAX_SECTIONS} " \
              "sections per page."
          end

          def example
            "Example — the shape, not your copy. Its `upload:N` tokens are illustrative; use only " \
              "tokens listed in the Website images section.\n\n```json\n#{json(EXAMPLE)}\n```"
          end

          def extraction = Websites::Assistant::Extraction
        end
      end
    end
  end
end
