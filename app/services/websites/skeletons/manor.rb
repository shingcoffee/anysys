# frozen_string_literal: true

module Websites
  module Skeletons
    # Sotheby's International Realty register: a quiet serif hero, featured
    # residences, the full portfolio, advisors and the office network.
    module Manor
      PAGES = [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "manor_home",
          "sections" => [
            {
              "type" => "hero_cinematic",
              "props" => {
                "kicker" => "Private residences since 1961",
                "headline" => "Extraordinary homes, quietly represented",
                "subhead" => "Estates, penthouses and country houses — presented to the buyers most likely to love them.",
                "primary_label" => "View residences",
                "primary_href" => "listings",
                "secondary_label" => "Speak with an advisor",
                "secondary_href" => "advisors",
                "tone" => "dark"
              }
            },
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "Featured",
                "heading" => "Residences of the season",
                "aspect" => "landscape",
                "listings" => [
                  { "title" => "Villa Serena", "meta" => "Montecito, California\n6 bedrooms · 8 baths · 2.1 acres", "price" => "$18,500,000", "badge" => "New", "href" => "listings" },
                  { "title" => "The Glass House", "meta" => "West Vancouver, British Columbia\n5 bedrooms · 6 baths · ocean frontage", "price" => "$12,900,000", "href" => "listings" },
                  { "title" => "Casa Mirador", "meta" => "Marbella, Spain\n6 bedrooms · 7 baths · sea views", "price" => "€9,750,000", "badge" => "Private", "href" => "listings" }
                ]
              }
            },
            {
              "type" => "statement",
              "props" => {
                "kicker" => "Our approach",
                "headline" => "Fewer listings, more attention. Every home is presented as if it were the only one.",
                "body" => "Architectural photography, a printed monograph and introductions through a private network of 26,000 advisors in 84 countries."
              }
            },
            {
              "type" => "proof_strip",
              "props" => {
                "items" => [
                  { "value" => "$4.2B", "label" => "sold last year" },
                  { "value" => "84", "label" => "countries" },
                  { "value" => "1,100", "label" => "offices" },
                  { "value" => "98%", "label" => "of asking price achieved" }
                ]
              }
            },
            {
              "type" => "testimonials",
              "props" => {
                "kicker" => "Clients",
                "heading" => "In their words",
                "items" => [
                  { "quote" => "They sold our family house to the one buyer who wanted to keep the garden exactly as my mother planted it.", "name" => "Eleanor Whitfield", "role" => "Seller, Cotswolds" },
                  { "quote" => "Discreet from the first call to the last signature. We never saw our address online.", "name" => "Marcus Hale", "role" => "Seller, Montecito" },
                  { "quote" => "Our advisor found the apartment before it was listed, and negotiated like it was her own.", "name" => "Sofia Laurent", "role" => "Buyer, Paris" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Considering a sale?",
                "body" => "Request a private valuation. An advisor will visit, listen and prepare a written recommendation within a week.",
                "button_label" => "Request a valuation",
                "button_href" => "advisors"
              }
            }
          ]
        },
        {
          "title" => "Residences",
          "slug" => "listings",
          "home" => false,
          "nav_visible" => true,
          "role" => "listings",
          "layout_key" => "manor_listings",
          "sections" => [
            {
              "type" => "listing_grid",
              "props" => {
                "kicker" => "Portfolio",
                "heading" => "Residences for sale",
                "subhead" => "A selection of our current portfolio. Many homes are offered privately — ask an advisor for the full list.",
                "aspect" => "portrait",
                "listings" => [
                  { "title" => "Villa Serena", "meta" => "Montecito, California\n6 bd · 8 ba", "price" => "$18,500,000", "badge" => "New", "href" => "https://example.com/residences/villa-serena" },
                  { "title" => "Maison Rivage", "meta" => "Cap Ferrat, France\n7 bd · 7 ba", "price" => "€24,000,000", "href" => "https://example.com/residences/maison-rivage" },
                  { "title" => "The Glass House", "meta" => "West Vancouver, Canada\n5 bd · 6 ba", "price" => "$12,900,000", "href" => "https://example.com/residences/glass-house" },
                  { "title" => "Villa Azure", "meta" => "Saint-Tropez, France\n5 bd · 6 ba", "price" => "€16,500,000", "badge" => "Private", "href" => "https://example.com/residences/villa-azure" },
                  { "title" => "Casa Mirador", "meta" => "Marbella, Spain\n6 bd · 7 ba", "price" => "€9,750,000", "href" => "https://example.com/residences/casa-mirador" },
                  { "title" => "Ridge House", "meta" => "Aspen, Colorado\n6 bd · 7 ba", "price" => "$21,750,000", "href" => "https://example.com/residences/ridge-house" },
                  { "title" => "Casa Alta", "meta" => "Mallorca, Spain\n5 bd · 5 ba", "price" => "€6,400,000", "badge" => "Reduced", "href" => "https://example.com/residences/casa-alta" },
                  { "title" => "Harbour Terrace", "meta" => "Sydney, Australia\n4 bd · 4 ba", "price" => "A$14,200,000", "href" => "https://example.com/residences/harbour-terrace" }
                ]
              }
            },
            {
              "type" => "cta_band",
              "props" => {
                "headline" => "Looking for something unlisted?",
                "body" => "Tell us what you are searching for. Our advisors hear about homes months before they reach the market.",
                "button_label" => "Start a private search",
                "button_href" => "advisors"
              }
            }
          ]
        },
        {
          "title" => "Advisors",
          "slug" => "advisors",
          "home" => false,
          "nav_visible" => true,
          "role" => "advisors",
          "layout_key" => "manor_advisors",
          "sections" => [
            {
              "type" => "team_grid",
              "props" => {
                "kicker" => "Advisors",
                "heading" => "The people who will represent you",
                "people" => [
                  { "name" => "Charlotte Ames", "role" => "Senior advisor, Montecito", "bio" => "Twenty-two years on the California coast." },
                  { "name" => "Henry Castell", "role" => "Managing director, London", "bio" => "Country houses and London townhouses." },
                  { "name" => "Isabelle Moreau", "role" => "Advisor, Côte d'Azur", "bio" => "Villas from Monaco to Saint-Tropez." },
                  { "name" => "James Whitaker", "role" => "Advisor, New York", "bio" => "Penthouses and pre-war co-ops." }
                ]
              }
            },
            {
              "type" => "steps",
              "props" => {
                "kicker" => "Selling with us",
                "heading" => "Four steps, one advisor",
                "items" => [
                  { "title" => "Valuation", "body" => "A private visit and a written recommendation within a week." },
                  { "title" => "Presentation", "body" => "Architectural photography, film and a printed monograph." },
                  { "title" => "Introduction", "body" => "Private previews for qualified buyers before any public launch." },
                  { "title" => "Negotiation", "body" => "One advisor from first viewing to exchange." }
                ]
              }
            },
            {
              "type" => "quote",
              "props" => {
                "quote" => "A great house deserves a buyer who understands it. Our job is to find that person, not just a price.",
                "attribution" => "Charlotte Ames",
                "role" => "Senior advisor"
              }
            }
          ]
        },
        {
          "title" => "Offices",
          "slug" => "offices",
          "home" => false,
          "nav_visible" => true,
          "role" => "offices",
          "layout_key" => "manor_offices",
          "sections" => [
            {
              "type" => "locations",
              "props" => {
                "kicker" => "Offices",
                "heading" => "Visit a gallery",
                "subhead" => "Each office doubles as a gallery of the homes we represent in the region.",
                "places" => [
                  { "name" => "Montecito", "address" => "1482 East Valley Road\nMontecito, CA", "hours" => "Monday–Saturday 10:00–18:00", "phone" => "+1 805 555 0120", "button_label" => "Book a visit", "button_href" => "https://example.com/offices/montecito" },
                  { "name" => "Mayfair", "address" => "31 Mount Street\nLondon W1K", "hours" => "Monday–Friday 9:00–18:00", "phone" => "+44 20 5555 0140", "button_label" => "Book a visit", "button_href" => "https://example.com/offices/mayfair" },
                  { "name" => "Saint-Jean-Cap-Ferrat", "address" => "4 Avenue Denis Séméria\n06230 Saint-Jean-Cap-Ferrat", "hours" => "Tuesday–Saturday 10:00–19:00", "phone" => "+33 4 55 55 01 60", "button_label" => "Book a visit", "button_href" => "https://example.com/offices/cap-ferrat" }
                ]
              }
            },
            {
              "type" => "contact_info",
              "props" => {
                "heading" => "Private enquiries",
                "address" => "31 Mount Street\nLondon W1K",
                "email" => "private@example.com",
                "phone" => "+44 20 5555 0100",
                "hours" => "Replies within one business day"
              }
            }
          ]
        }
      ].freeze
    end
  end
end
