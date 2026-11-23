# Constants Multi-Tenancy Update

## Summary
Added `customer_id` field to Constants model to support multi-tenancy, similar to the Flowcharts model behavior.

## Changes Made

### 1. Database Migration
**File**: `db/migrate/20260225064039_add_customer_to_constants.rb`

- Added `customer_id` integer column (nullable)
- Set `customer_id` to NULL for all shared constants
- Added index on `customer_id`
- Added partial unique index on `(customer_id, name)` where `customer_id IS NOT NULL`

**Schema Changes:**
```ruby
# Before
t.string :name, null: false              # Simple non-unique index
t.string :constant_type, null: false
t.json :options, default: []

# After
t.string :name, null: false              # Non-unique index
t.string :constant_type, null: false
t.json :options, default: []
t.integer :customer_id                   # NEW - nullable, indexed

# New Index
add_index :constants, [:customer_id, :name],
          unique: true,
          where: "customer_id IS NOT NULL",
          name: "index_constants_on_customer_id_and_name_for_customer_specific"
```

### 2. Model Updates
**File**: `app/models/constant.rb`

#### Added Association
```ruby
belongs_to :customer, optional: true
```

#### Updated Validations
```ruby
# Before
validates :name, presence: true, uniqueness: true

# After
validates :name, presence: true
validates :name, uniqueness: { scope: :customer_id }, if: :type_customer_specific?
validates :name, uniqueness: true, if: :type_shared?
validate :customer_required_for_customer_specific_type
```

#### Added Callbacks
```ruby
before_validation :clear_customer_for_shared

def clear_customer_for_shared
  self.customer_id = nil if type_shared?
end

def customer_required_for_customer_specific_type
  if type_customer_specific? && customer_id.blank?
    errors.add(:customer_id, "is required when type is Customer Specific")
  elsif type_shared? && customer_id.present?
    errors.add(:customer_id, "must be empty when type is Shared")
  end
end
```

#### Added Scope
```ruby
scope :accessible, -> {
  if Current.customer?
    where(customer_id: Current.customer_id).or(where(constant_type: "shared"))
  else
    where(constant_type: "shared")
  end
}
```

### 3. Controller Updates
**File**: `app/controllers/constants_controller.rb`

#### Index Action
```ruby
# Before
@constants = Constant.ordered

# After
@constants = Constant.accessible.ordered
```

#### Create Action
```ruby
def create
  @constant = Constant.new(constant_params)
  @constant.customer = current_customer if @constant.type_customer_specific?
  # ... rest of code
end
```

### 4. View Updates

#### Index View (`app/views/constants/index.html.erb`)
- Added customer badge display for customer_specific constants
- Shows customer name next to the type badge

#### Show View (`app/views/constants/show.html.erb`)
- Added customer badge display for customer_specific constants

### 5. Factory Updates
**File**: `spec/factories/constants.rb`

```ruby
factory :constant do
  sequence(:name) { |n| "Constant #{n}" }
  constant_type { "shared" }
  options { ["Option 1", "Option 2", "Option 3"] }
  customer { nil }

  trait :shared do
    constant_type { "shared" }
    customer { nil }
  end

  trait :customer_specific do
    constant_type { "customer_specific" }
    association :customer
  end
end
```

### 6. Test Updates

#### Model Specs (`spec/models/constant_spec.rb`)
- Added tests for customer association
- Updated uniqueness validation tests for scoped behavior
- Added tests for `accessible` scope
- Added tests for customer_id requirements based on type

#### Controller Specs (`spec/controllers/constants_controller_spec.rb`)
- Added Current.customer_id setup
- Updated index specs to test accessible scope
- Updated create specs to test both shared and customer_specific creation
- Verified customer_id is set correctly based on type

## Behavior Comparison

### Flowcharts Model
| Aspect | Custom | Blueprint |
|--------|--------|-----------|
| customer_id | Required | NULL |
| entity_id | Required | NULL |
| Visibility | Customer-scoped | Shared |
| Name uniqueness | Within customer | Global |

### Constants Model
| Aspect | Customer Specific | Shared |
|--------|------------------|--------|
| customer_id | Required | NULL |
| Visibility | Customer-scoped | Shared |
| Name uniqueness | Within customer | Global |

## Usage Examples

### Creating Shared Constant
```ruby
# Available to all customers
constant = Constant.create!(
  name: "Countries",
  constant_type: "shared",
  options: ["USA", "Canada", "Mexico"]
)
# customer_id will be automatically set to nil
```

### Creating Customer-Specific Constant
```ruby
# Only visible to specific customer
customer = Customer.find(12345678)
constant = Constant.create!(
  name: "Custom Status",
  constant_type: "customer_specific",
  customer: customer,
  options: ["Active", "Inactive"]
)
```

### Querying Accessible Constants
```ruby
# Within a customer context
Current.customer_id = 12345678
constants = Constant.accessible  # Returns customer's + shared constants

# Without customer context
Current.reset
constants = Constant.accessible  # Returns only shared constants
```

### Name Uniqueness
```ruby
# Shared constants - globally unique
Constant.create!(name: "Countries", constant_type: "shared", options: ["USA"])
Constant.create!(name: "Countries", constant_type: "shared", options: ["UK"])
# => Error: name has already been taken

# Customer-specific - unique within customer
customer1 = Customer.find(12345678)
customer2 = Customer.find(87654321)

Constant.create!(name: "Status", constant_type: "customer_specific", customer: customer1, options: ["A"])
Constant.create!(name: "Status", constant_type: "customer_specific", customer: customer2, options: ["B"])
# => Success! Same name for different customers is allowed
```

## Test Results
- ✅ Model specs: 22 examples, 0 failures
- ✅ Controller specs: 25 examples, 0 failures

## Migration Status
```bash
== 20260225064039 AddCustomerToConstants: migrating ===========================
-- add_column(:constants, :customer_id, :integer)
   -> 0.0019s
-- execute("UPDATE constants\nSET customer_id = NULL\nWHERE constant_type = 'shared'\n")
   -> 0.0007s
-- add_index(:constants, :customer_id)
   -> 0.0008s
-- add_index(:constants, [:customer_id, :name], ...)
   -> 0.0007s
== 20260225064039 AddCustomerToConstants: migrated (0.0043s) ==================
```

## Documentation Updates
- ✅ Updated `docs/features/constants/DATA_STRUCTURE.md` with multi-tenancy information
- ✅ Added database schema updates
- ✅ Added multi-tenancy behavior section
- ✅ Added usage examples for both types
- ✅ Updated all JSON examples to include customer_id

## Benefits

1. **Tenant Isolation**: Customer-specific constants are isolated per customer
2. **Shared Resources**: Common constants can be shared across all customers
3. **Flexibility**: Each customer can have custom options while using shared ones
4. **Consistency**: Follows the same pattern as Flowcharts model
5. **Database Integrity**: Partial unique index ensures data consistency

## Backward Compatibility

All existing constants remain valid:
- Existing shared constants have `customer_id = NULL` (set by migration)
- Application logic handles both shared and customer-specific constants
- No breaking changes to existing API or functionality
