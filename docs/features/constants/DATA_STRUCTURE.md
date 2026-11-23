# Constants Data Structure

## Database Schema

```
Table: constants
┌──────────────────┬──────────────┬──────────┬────────────┬─────────┐
│ Column           │ Type         │ Null     │ Default    │ Index   │
├──────────────────┼──────────────┼──────────┼────────────┼─────────┤
│ id               │ INTEGER      │ NOT NULL │            │ PRIMARY │
│ name             │ VARCHAR      │ NOT NULL │            │ YES     │
│ constant_type    │ VARCHAR      │ NOT NULL │            │ YES     │
│ options          │ JSON         │ NULL     │ []         │         │
│ customer_id      │ INTEGER      │ NULL     │            │ YES     │
│ created_at       │ DATETIME(6)  │ NOT NULL │            │         │
│ updated_at       │ DATETIME(6)  │ NOT NULL │            │         │
└──────────────────┴──────────────┴──────────┴────────────┴─────────┘
```

## Field Details

### 1. `id` (INTEGER, PRIMARY KEY)
- Auto-incrementing unique identifier
- Example: `1`, `2`, `3`

### 2. `name` (VARCHAR, NOT NULL, INDEXED)
- Human-readable name of the constant
- **Uniqueness:**
  - For `shared`: globally unique
  - For `customer_specific`: unique within customer scope
- Examples: `"Countries"`, `"Status Types"`, `"Priority Levels"`

### 3. `constant_type` (VARCHAR, NOT NULL, INDEXED)
- Type of constant - determines visibility/scope
- **Enum values:**
  - `"shared"` - Available to all customers, customer_id must be NULL
  - `"customer_specific"` - Only for specific customer, customer_id required
- Examples: `"shared"`, `"customer_specific"`

### 4. `options` (JSON, DEFAULT: [])
- Array of string values representing available options
- Stored as JSON in database
- Can be empty array or contain multiple values
- Examples:
  ```json
  ["United States", "Canada", "Mexico"]
  ["Active", "Inactive", "Pending", "Archived"]
  ["Low", "Medium", "High", "Critical"]
  []
  ```

### 5. `customer_id` (INTEGER, NULL, INDEXED)
- Foreign key to `customers` table
- **Required** for customer_specific constants (type = "customer_specific")
- **Must be NULL** for shared constants (type = "shared")
- Provides tenant isolation for customer_specific constants
- Example: `12345678`, `NULL`

### 6. `created_at` (DATETIME(6), NOT NULL)
- Timestamp when record was created
- Automatically set by Rails
- Example: `"2026-02-25 06:33:53.605429000 +0000"`

### 7. `updated_at` (DATETIME(6), NOT NULL)
- Timestamp when record was last updated
- Automatically updated by Rails
- Example: `"2026-02-25 06:33:53.605429000 +0000"`

## JSON Structure

### Complete Record (JSON format)

#### Shared Constant
```json
{
  "id": 1,
  "name": "Countries",
  "constant_type": "shared",
  "customer_id": null,
  "options": [
    "United States",
    "Canada",
    "Mexico",
    "United Kingdom",
    "Germany",
    "France"
  ],
  "created_at": "2026-02-25T06:33:53.605Z",
  "updated_at": "2026-02-25T06:33:53.605Z"
}
```

#### Customer-Specific Constant
```json
{
  "id": 2,
  "name": "Custom Status Types",
  "constant_type": "customer_specific",
  "customer_id": 12345678,
  "options": [
    "Active",
    "Inactive",
    "Pending"
  ],
  "created_at": "2026-02-25T06:35:00.000Z",
  "updated_at": "2026-02-25T06:35:00.000Z"
}
```

## Ruby Object Structure

### ActiveRecord Model
```ruby
#<Constant:0x00007f...
  id: 1,
  name: "Countries",
  constant_type: "shared",
  options: ["United States", "Canada", "Mexico", "United Kingdom", "Germany", "France"],
  created_at: 2026-02-25 06:33:53 UTC,
  updated_at: 2026-02-25 06:33:53 UTC
>
```

## Data Examples

### Example 1: Countries (Shared)
```ruby
{
  id: 1,
  name: "Countries",
  constant_type: "shared",
  options: [
    "United States",
    "Canada",
    "Mexico",
    "United Kingdom",
    "Germany",
    "France",
    "Japan",
    "Australia"
  ],
  created_at: "2026-02-25T06:33:53.605Z",
  updated_at: "2026-02-25T06:33:53.605Z"
}
```

### Example 2: Status Types (Customer Specific)
```ruby
{
  id: 2,
  name: "Status Types",
  constant_type: "customer_specific",
  customer_id: 12345678,
  options: [
    "Active",
    "Inactive",
    "Pending",
    "Archived",
    "Draft"
  ],
  created_at: "2026-02-25T06:33:53.611Z",
  updated_at: "2026-02-25T06:33:53.611Z"
}
```

### Example 3: Priority Levels (Shared)
```ruby
{
  id: 3,
  name: "Priority Levels",
  constant_type: "shared",
  options: [
    "Low",
    "Medium",
    "High",
    "Critical"
  ],
  created_at: "2026-02-25T06:33:53.628Z",
  updated_at: "2026-02-25T06:33:53.628Z"
}
```

### Example 4: Languages (Shared)
```ruby
{
  id: 4,
  name: "Languages",
  constant_type: "shared",
  options: [
    "English",
    "Spanish",
    "French",
    "German",
    "Chinese",
    "Japanese"
  ],
  created_at: "2026-02-25T06:35:00.000Z",
  updated_at: "2026-02-25T06:35:00.000Z"
}
```

### Example 5: Empty Options
```ruby
{
  id: 5,
  name: "Future Options",
  constant_type: "shared",
  options: [],
  created_at: "2026-02-25T06:36:00.000Z",
  updated_at: "2026-02-25T06:36:00.000Z"
}
```

## Accessing Data in Ruby

### Basic Access
```ruby
constant = Constant.find(1)

constant.id             # => 1
constant.name           # => "Countries"
constant.constant_type  # => "shared"
constant.options        # => ["United States", "Canada", "Mexico", ...]
```

### Enum Methods
```ruby
constant.type_shared?              # => true
constant.type_customer_specific?   # => false

# Change type
constant.constant_type = "customer_specific"
constant.type_customer_specific?   # => true
```

### Working with Options Array
```ruby
# Get options
constant.options                   # => ["United States", "Canada", ...]
constant.options.length            # => 6
constant.options.first             # => "United States"
constant.options.last              # => "France"

# Iterate options
constant.options.each do |option|
  puts option
end

# Add option
constant.options << "Italy"
constant.save

# Remove option
constant.options.delete("Mexico")
constant.save

# Replace all options
constant.options = ["New", "Options", "List"]
constant.save
```

### Associations
```ruby
constant.customer  # => Customer object (if customer_specific)
```

### Scopes
```ruby
# Get all shared constants
Constant.shared

# Get all customer-specific constants
Constant.customer_specific

# Get all ordered by name
Constant.ordered

# Get accessible constants (current customer's + shared)
# Requires Current.customer_id to be set
Current.customer_id = 12345678
Constant.accessible  # => Customer's constants + shared constants

# Without current customer, returns only shared
Current.reset
Constant.accessible  # => Only shared constants

# Combine scopes
Constant.shared.ordered
Constant.accessible.ordered
```

## Form Data Structure (POST/PATCH)

### Create/Update Request
```ruby
# Form params
params = {
  constant: {
    name: "Countries",
    constant_type: "shared",
    options: ["USA", "Canada", "Mexico"]  # Array of strings
  }
}

# In controller - options is automatically converted
constant_params.permit(:name, :constant_type, options: [])
```

### JSON API Request
```json
POST /12345678/constants
Content-Type: application/json

{
  "constant": {
    "name": "Countries",
    "constant_type": "shared",
    "options": ["USA", "Canada", "Mexico"]
  }
}
```

## Database Indices

| Index Name | Columns | Unique | Where Clause |
|------------|---------|--------|--------------|
| PRIMARY | id | Yes | - |
| index_constants_on_customer_id_and_name_for_customer_specific | customer_id, name | Yes | customer_id IS NOT NULL |
| index_constants_on_customer_id | customer_id | No | - |
| index_constants_on_constant_type | constant_type | No | - |
| index_constants_on_name | name | No | - |

## Database Constraints

1. **NOT NULL**: `id`, `name`, `constant_type`, `created_at`, `updated_at`
2. **UNIQUE**:
   - `name` globally for shared constants (enforced at application level)
   - `(customer_id, name)` for customer_specific constants (enforced at database level with partial unique index)
3. **DEFAULT**: `options` defaults to `[]` (empty array)
4. **INDEXED**: `name`, `constant_type`, `customer_id`

## Multi-Tenancy Behavior

### Shared Constants (`constant_type: "shared"`)
- **customer_id**: Must be NULL (automatically cleared on save)
- **Visibility**: Available to all customers
- **Uniqueness**: Name must be globally unique
- **Use case**: Common dropdown options like Countries, Languages, etc.

### Customer-Specific Constants (`constant_type: "customer_specific"`)
- **customer_id**: Required (must be set to a valid customer ID)
- **Visibility**: Only visible to the owning customer
- **Uniqueness**: Name must be unique within the customer scope
- **Use case**: Custom statuses, categories specific to one customer

### Automatic Behavior
```ruby
# Creating a shared constant automatically clears customer_id
constant = Constant.create!(
  name: "Countries",
  constant_type: "shared",
  customer_id: 12345678  # This will be cleared
)
constant.customer_id  # => nil

# Creating a customer_specific constant requires customer_id
constant = Constant.create!(
  name: "Custom Status",
  constant_type: "customer_specific",
  customer_id: nil  # This will fail validation
)
# => ActiveRecord::RecordInvalid: customer_id is required when type is Customer Specific
```

## Valid constant_type Values

| Value               | Description                     | customer_id           |
|---------------------|---------------------------------|-----------------------|
| `shared`            | Available to all customers      | NULL (required)       |
| `customer_specific` | Only for specific customer      | Required (not NULL)   |

## Options Array Rules

- **Type**: Must be a JSON array
- **Content**: Typically strings, but can be any JSON-serializable values
- **Empty**: Can be an empty array `[]`
- **Duplicates**: Allowed (no uniqueness constraint)
- **Order**: Preserved as entered
- **Max Size**: Limited by JSON column size (typically ~1GB in PostgreSQL, ~1MB in SQLite)

## Use Cases

### 1. Dropdown Options for Forms
```ruby
# In entity attribute configuration
constant = Constant.find_by(name: "Countries")
options_for_select(constant.options)
```

### 2. Validation Lists
```ruby
# Validate value is in constant options
validates :country, inclusion: { in: -> { Constant.find_by(name: "Countries")&.options || [] } }
```

### 3. Dynamic Configuration
```ruby
# Get available statuses
statuses = Constant.find_by(name: "Status Types")&.options || ["Active", "Inactive"]
```

### 4. Multi-tenant Constants
```ruby
# Shared across all customers
global_constants = Constant.shared

# Specific to current customer
customer_constants = Constant.customer_specific
```

## Migration Example

```ruby
# Creating a shared constant (available to all customers)
Constant.create!(
  name: "Payment Methods",
  constant_type: "shared",
  options: ["Credit Card", "Debit Card", "PayPal", "Bank Transfer", "Cash"]
)

# Creating a customer-specific constant
customer = Customer.find(12345678)
Constant.create!(
  name: "Custom Status",
  constant_type: "customer_specific",
  customer: customer,
  options: ["Active", "Inactive", "Pending"]
)

# Updating options
constant = Constant.find_by(name: "Payment Methods")
constant.options << "Apple Pay"
constant.options << "Google Pay"
constant.save!

# Changing type from customer_specific to shared
# (customer_id will be automatically set to nil)
constant.update!(constant_type: "shared")
```
