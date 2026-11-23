# frozen_string_literal: true

FactoryBot.define do
  factory :website do
    customer
    sequence(:name) { |n| "Site #{n}" }
    tagline { "A public introduction site" }
    published { false }
    skeleton_key { "presence" }
    theme { Website::DEFAULT_THEME.dup }
    seo { {} }
    footer { {} }

    trait :published do
      published { true }
    end
  end

  factory :website_page do
    website
    customer { website.customer }
    sequence(:title) { |n| "Page #{n}" }
    sequence(:slug) { |n| "page-#{n}" }
    position { 0 }
    published { false }
    home { false }
    nav_visible { true }
    sections { [] }

    trait :published do
      published { true }
    end

    trait :home do
      home { true }
      slug { "" }
      title { "Home" }
    end
  end

  factory :website_layout do
    sequence(:key) { |n| "layout_#{n}" }
    sequence(:name) { |n| "Layout #{n}" }
    description { "A page composition" }
    position { 0 }
    archived { false }
    sections do
      [ { "id" => "sec_rich", "type" => "rich_text", "props" => { "heading" => "Hello", "body" => "Body copy." } } ]
    end
  end

  factory :website_skeleton do
    sequence(:key) { |n| "skeleton_#{n}" }
    sequence(:name) { |n| "Skeleton #{n}" }
    description { "A multi-page starter" }
    position { 0 }
    archived { false }
    pages do
      [
        {
          "title" => "Home",
          "slug" => "",
          "home" => true,
          "nav_visible" => true,
          "role" => "home",
          "layout_key" => "article",
          "sections" => [ { "type" => "rich_text", "props" => { "heading" => "Home", "body" => "Welcome." } } ]
        }
      ]
    end
  end
end
