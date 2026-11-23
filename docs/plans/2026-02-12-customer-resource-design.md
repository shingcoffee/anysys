# Customer Resource Design

## Overview

Add a new `Customer` resource with full CRUD functionality following existing codebase patterns.

## Requirements

- **Fields**: name, alias, address, contact, phone, tier
- **ID**: Random 8-digit integer (10000000-99999999)
- **Tier**: Enum (basic, standard, premium, enterprise)
- **Soft Delete**: Yes (active/inactive status)
- **Validations**: Name required only

---

## 1. Database Schema

### Table: `customers`

| Column | Type | Constraints | Default |
|--------|------|-------------|---------|
| `id` | integer | PK, 8-digit random | - |
| `name` | string | NOT NULL | - |
| `alias` | string | - | - |
| `address` | text | - | - |
| `contact` | string | - | - |
| `phone` | string | - | - |
| `tier` | integer | NOT NULL | 0 (basic) |
| `status` | integer | NOT NULL | 0 (active) |
| `created_at` | datetime | NOT NULL | - |
| `updated_at` | datetime | NOT NULL | - |

### Indexes

- `index_customers_on_name`
- `index_customers_on_tier`
- `index_customers_on_status`
- `index_customers_on_created_at`

### Enums

- `tier`: `{ basic: 0, standard: 1, premium: 2, enterprise: 3 }`
- `status`: `{ active: 0, inactive: 1 }`

---

## 2. Model

### `app/models/customer.rb`

```ruby
class Customer < ApplicationRecord
  include SoftDeletable
  include RandomIdGeneratable

  soft_deletable deleted_status: :inactive
  random_id digits: 8

  enum :status, { active: 0, inactive: 1 }, default: :active
  enum :tier, { basic: 0, standard: 1, premium: 2, enterprise: 3 }, default: :basic

  validates :name, presence: true, length: { maximum: 100 }

  scope :by_name, -> { order(:name) }
  scope :by_tier, ->(tier) { where(tier: tier) }
  scope :search_by_name, ->(query) { where("LOWER(name) LIKE ?", "%#{query.downcase}%") if query.present? }

  default_scope { visible }
end
```

### New Concern: `app/models/concerns/random_id_generatable.rb`

Provides random N-digit integer ID generation:

- Override ID before create
- Generate random integers within range (10^(n-1) to 10^n - 1)
- Retry on collision (uniqueness guaranteed)
- Works with SQLite integer primary key

---

## 3. Controller

### `app/controllers/customers_controller.rb`

```ruby
class CustomersController < ApplicationController
  include SoftDeletableController
  soft_deletable Customer

  before_action :set_customer, only: %i[show edit update destroy]
  before_action :set_deleted_customer, only: %i[restore]

  def index
    @customers = Customer.by_name
    @customers = @customers.search_by_name(params[:search]) if params[:search].present?
    @customers = @customers.by_tier(params[:tier]) if params[:tier].present?
  end

  def show; end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)
    if @customer.save
      redirect_to @customer, notice: "Customer was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @customer.update(customer_params)
      redirect_to @customer, notice: "Customer was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @customer.soft_delete
    redirect_to customers_url, notice: "Customer was successfully deleted."
  end

  private

  def set_customer
    @customer = Customer.find(params[:id])
  end

  def set_deleted_customer
    @customer = Customer.only_deleted.find(params[:id])
  end

  def customer_params
    params.require(:customer).permit(:name, :alias, :address, :contact, :phone, :tier)
  end
end
```

### Routes

```ruby
resources :customers do
  member do
    patch :restore
  end
  collection do
    get :trash
    delete :empty_trash
  end
end
```

---

## 4. ViewComponents

### Components

| Component | Purpose |
|-----------|---------|
| `CustomerListTableComponent` | Table displaying customers with actions |
| `CustomerFormComponent` | Reusable form for new/edit |
| `CustomerCardComponent` | Detail view card for show page |
| `TierBadgeComponent` | Styled badge showing tier level |

### TierBadgeComponent

```ruby
class TierBadgeComponent < ApplicationComponent
  TIER_STYLES = {
    basic: "bg-gray-100 text-gray-800",
    standard: "bg-blue-100 text-blue-800",
    premium: "bg-purple-100 text-purple-800",
    enterprise: "bg-amber-100 text-amber-800"
  }.freeze

  def initialize(tier:)
    @tier = tier.to_sym
  end

  def tier_classes
    TIER_STYLES[@tier] || TIER_STYLES[:basic]
  end
end
```

### Views Structure

```
app/views/customers/
├── index.html.erb   # Uses CustomerListTableComponent
├── show.html.erb    # Uses CustomerCardComponent
├── new.html.erb     # Uses CustomerFormComponent
├── edit.html.erb    # Uses CustomerFormComponent
└── trash.html.erb   # Uses CustomerListTableComponent (deleted)
```

---

## 5. Tests (RSpec)

### Test Files

```
spec/
├── models/
│   └── customer_spec.rb
├── controllers/
│   └── customers_controller_spec.rb
├── components/
│   ├── customer_list_table_component_spec.rb
│   ├── customer_form_component_spec.rb
│   ├── customer_card_component_spec.rb
│   └── tier_badge_component_spec.rb
└── concerns/
    └── random_id_generatable_spec.rb
```

### Coverage

- **Model**: validations, enum values, scopes, soft delete, random ID generation
- **Controller**: all CRUD actions, trash/restore/empty_trash, search/filter
- **Components**: rendering, conditional display, styling

---

## 6. Files to Create

1. `db/migrate/YYYYMMDDHHMMSS_create_customers.rb`
2. `app/models/customer.rb`
3. `app/models/concerns/random_id_generatable.rb`
4. `app/controllers/customers_controller.rb`
5. `app/components/customer_list_table_component.rb`
6. `app/components/customer_list_table_component.html.erb`
7. `app/components/customer_form_component.rb`
8. `app/components/customer_form_component.html.erb`
9. `app/components/customer_card_component.rb`
10. `app/components/customer_card_component.html.erb`
11. `app/components/tier_badge_component.rb`
12. `app/components/tier_badge_component.html.erb`
13. `app/views/customers/index.html.erb`
14. `app/views/customers/show.html.erb`
15. `app/views/customers/new.html.erb`
16. `app/views/customers/edit.html.erb`
17. `app/views/customers/trash.html.erb`
18. `config/routes.rb` (update)
19. `spec/models/customer_spec.rb`
20. `spec/controllers/customers_controller_spec.rb`
21. `spec/components/customer_list_table_component_spec.rb`
22. `spec/components/customer_form_component_spec.rb`
23. `spec/components/customer_card_component_spec.rb`
24. `spec/components/tier_badge_component_spec.rb`
25. `spec/models/concerns/random_id_generatable_spec.rb`
