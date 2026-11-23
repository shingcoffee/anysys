# frozen_string_literal: true

module WebsitesComponentHelpers
  def website_theme(tokens = {})
    Websites::Theme.new(tokens)
  end

  def website_record(attrs = {})
    OpenStruct.new({
      name: "Acme Institute",
      tagline: "Craft, research, and public programs",
      customer_id: 12345678,
      theme: {},
      seo: { "title" => "Acme", "description" => "An introduction." },
      footer: {
        "blurb" => "Quiet rooms for ambitious work.",
        "columns" => [
          {
            "heading" => "Visit",
            "links" => [{ "label" => "About", "url" => "about" }]
          }
        ]
      }
    }.merge(attrs))
  end

  def website_page_record(attrs = {})
    OpenStruct.new({
      title: "Home",
      slug: "",
      home: true,
      customer_id: 12345678,
      sections: []
    }.merge(attrs))
  end
end

RSpec.configure do |config|
  config.include WebsitesComponentHelpers, type: :component
end
