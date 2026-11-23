# frozen_string_literal: true

class PageLayoutTemplates
  module Templates
    module Food
      module RecipeSubmission
        DEFINITION = {
          key: "recipe_submission",
          name: "Recipe Submission",
          description: "Community recipe sharing with ingredients, steps, and photo upload",
          category: "food",
          theme_preset: "playful",
          preview_rows: [
            [{ type: :section, label: "Recipe Info" }],
            [{ type: :input, width: "half", label: "Recipe Name" }, { type: :input, width: "half", label: "Submitted By" }],
            [{ type: :select, width: "half", label: "Cuisine Type" }, { type: :select, width: "half", label: "Category (Appetizer, Main, Side, Dessert, Drink, Snack, Breakfast)" }],
            [{ type: :select, width: "half", label: "Difficulty (Easy, Medium, Hard)" }, { type: :select, width: "half", label: "Diet Type (None, Vegetarian, Vegan, Gluten-Free, Keto, Paleo, Dairy-Free)" }],
            [{ type: :number, width: "third", label: "Prep Time (min)" }, { type: :number, width: "third", label: "Cook Time (min)" }, { type: :number, width: "third", label: "Servings" }],
            [{ type: :divider }],
            [{ type: :section, label: "Ingredients & Instructions" }],
            [{ type: :textarea, width: "full", label: "Ingredients (one per line with amounts)" }],
            [{ type: :textarea, width: "full", label: "Step-by-Step Instructions" }],
            [{ type: :textarea, width: "full", label: "Chef's Tips & Notes" }],
            [{ type: :divider }],
            [{ type: :section, label: "Media & Sharing" }],
            [{ type: :checkbox, width: "full", label: "Allergens Present (Gluten, Dairy, Eggs, Nuts, Shellfish, Soy, Sesame, Sulfites)" }],
            [{ type: :file, width: "full", label: "Upload Recipe Photo(s)" }],
            [{ type: :checkbox, width: "full", label: "I give permission to publish this recipe on the platform with my name" }]
          ],
          layout: {
            default_width: "half",
            field_width_rules: {
              "text" => "half",
              "email" => "half",
              "select" => "half",
              "number" => "third",
              "textarea" => "full",
              "checkbox" => "full",
              "file" => "full"
            },
            sections: [
              { label: "Recipe Info", match_types: %w[text email select number] },
              { label: "Ingredients & Instructions", match_types: %w[textarea] },
              { label: "Media & Sharing", match_types: %w[file checkbox] }
            ],
            inject_elements: [
              { after_section: 0, type: "divider" }, { after_section: 1, type: "divider" }
            ]
          }
        }.freeze
      end
    end
  end
end
