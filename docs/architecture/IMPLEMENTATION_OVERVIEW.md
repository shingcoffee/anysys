# Generic Model Extensibility - Implementation Overview

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         ANY BASE MODEL (User, Product, Order, etc.)      │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  class User < ApplicationRecord                                    │  │
│  │    include Extendable  ← Single line makes model extensible       │  │
│  │  end                                                               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────┬──────────────────────────────────────────┘
                               │ has_many :extended_model_entries
                               │ (polymorphic)
                               ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                      ExtendedModelEntry (Join Table)                     │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  • extendable_type: "User"                                         │  │
│  │  • extendable_id: 123                                              │  │
│  │  • entity_id: 5 (references Employee schema)                       │  │
│  │  • entity_entry_id: 789 (references actual data)                   │  │
│  │  • customer_id: 1 (tenant isolation)                               │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└────────────┬─────────────────────────────────────────┬──────────────────┘
             │ belongs_to :entity                      │ belongs_to :entity_entry
             ↓                                         ↓
┌──────────────────────────┐           ┌─────────────────────────────────┐
│   Entity (Schema)        │           │   EntityEntry (Data)            │
│  ┌────────────────────┐  │           │  ┌───────────────────────────┐  │
│  │ name: "Employee"   │  │           │  │ property_data: {          │  │
│  │ property_schema: { │  │           │  │   "position": "Developer",│  │
│  │   position: String,│  │           │  │   "department": "Eng",    │  │
│  │   department: Str, │  │           │  │   "salary": 120000        │  │
│  │   salary: Float    │  │           │  │ }                         │  │
│  │ }                  │  │           │  └───────────────────────────┘  │
│  └────────────────────┘  │           └─────────────────────────────────┘
│  (defines structure)     │           (stores actual values)
└──────────────────────────┘
```

## Key Components

### 1. **Extendable Concern** (`app/models/concerns/extendable.rb`)
The core module that makes ANY model extensible with just one line of code.

**What it provides:**
- Polymorphic associations to `extended_model_entries`
- Instance methods: `extension_data()`, `set_extension_data()`, `has_extension?()`
- Class methods: `where_extension()`, `of_extension_type()`, `create_with_extension()`
- Scopes: `with_extension()`, `with_extensions`, `without_extensions`

**Usage:**
```ruby
class User < ApplicationRecord
  include Extendable  # ← That's it! Now User is fully extensible
end

class Product < ApplicationRecord
  include Extendable  # ← Products can also be extended
end
```

### 2. **ExtendedModelEntry** (`app/models/extended_model_entry.rb`)
Polymorphic join table that links any base model to its extensions.

**Key Features:**
- Polymorphic `extendable` association (works with User, Product, Order, etc.)
- Links to Entity (schema) and EntityEntry (data)
- Enforces uniqueness: one extension of each type per record
- Provides multi-tenant isolation via `customer_id`

### 3. **Database Migration**
```ruby
create_table :extended_model_entries do |t|
  t.references :extendable, polymorphic: true, null: false  # Links to ANY model
  t.references :entity, null: false, foreign_key: true      # Schema definition
  t.references :entity_entry, null: false, foreign_key: true # Actual data
  t.references :customer, null: false, foreign_key: true     # Tenant isolation
  t.timestamps
end

# Ensures one extension of each type per record
add_index :extended_model_entries,
  [:extendable_type, :extendable_id, :entity_id],
  unique: true
```

### 4. **ExtendedModelService** (`app/services/extended_model_service.rb`)
High-level service layer for managing extended models.

**Key Methods:**
- `create(model_class, base_attrs, extension_type, extension_attrs, customer:)`
- `update(record, base_attrs, extension_attrs)`
- `attach_extension(record, entity, attrs, customer)`
- `detach_extension(record, entity_or_name)`
- `query_by_extension(model_class, entity_name, filters, customer:)`
- `extension_stats(model_class, customer:)`

### 5. **ExtendedModelQueryBuilder** (`app/services/extended_model_query_builder.rb`)
Fluent query builder for complex queries on base + extension attributes.

**Key Methods:**
- `of_type(extension_type)` - Filter by extension type
- `where_extension(type, attribute, value)` - Filter by extension attribute
- `with_extensions` - Eager load extension data
- `where(conditions)` - Filter by base attributes
- `order()`, `limit()`, `offset()`, `paginate()` - Standard query methods

## How It Works - Complete Flow

### Example: Creating an Employee (User with Employee Extension)

**Step 1: Define the Extension Schema (one-time setup)**
```ruby
# Admin creates an Employee entity type
employee_entity = Entity.create!(
  name: 'Employee',
  name_slug: 'employee',
  customer: customer,
  property_schema: [
    {
      name: 'Position',
      name_slug: 'position',
      type: 'String',
      validators: ['presence']
    },
    {
      name: 'Department',
      name_slug: 'department',
      type: 'String',
      validators: ['presence']
    },
    {
      name: 'Salary',
      name_slug: 'salary',
      type: 'Float',
      validators: ['numericality']
    }
  ].to_json
)
```

**Step 2: Create a User with Employee Extension**
```ruby
# Using the service layer (recommended)
employee = ExtendedModelService.create(
  User,                                    # Base model class
  {                                        # Base attributes
    first_name: 'John',
    last_name: 'Doe',
    email: 'john@example.com',
    gender: 'male'
  },
  'Employee',                              # Extension type name
  {                                        # Extension attributes
    position: 'Senior Software Engineer',
    department: 'Engineering',
    salary: 120000.00
  },
  customer: customer
)

# What happens behind the scenes:
# 1. Creates User record: User.create!(first_name: 'John', ...)
# 2. Creates EntityEntry: EntityEntry.create!(entity: employee_entity, property_data: {...})
# 3. Creates ExtendedModelEntry linking User → Entity → EntityEntry
# 4. All wrapped in a database transaction
```

**Step 3: Access Extension Data**
```ruby
# Get all employee data
employee_data = employee.extension_data('Employee')
# => {
#   "position" => "Senior Software Engineer",
#   "department" => "Engineering",
#   "salary" => 120000.0
# }

# Access specific fields
position = employee_data['position']  # => "Senior Software Engineer"

# Check if user has extension
employee.has_extension?('Employee')  # => true

# Get all extension names
employee.extension_names  # => ["Employee"]

# Get merged attributes (base + extension)
full_attrs = employee.full_attributes('Employee')
# => {
#   "first_name" => "John",
#   "last_name" => "Doe",
#   "email" => "john@example.com",
#   "position" => "Senior Software Engineer",
#   "department" => "Engineering",
#   "salary" => 120000.0
# }
```

**Step 4: Query by Extension Attributes**
```ruby
# Using model class methods
engineers = User.where_extension('Employee', 'department', 'Engineering')
all_employees = User.of_extension_type('Employee')

# Using query builder (recommended for complex queries)
senior_engineers = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')                              # Only employees
  .where_extension('Employee', 'department', 'Engineering')  # In Engineering
  .where_extension('Employee', 'position', 'Senior Software Engineer')  # Senior level
  .where(status: 'active')                          # Active users
  .with_extensions                                  # Eager load extension data
  .order(:created_at, :desc)                        # Most recent first
  .all

# Get count
engineer_count = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')
  .where_extension('Employee', 'department', 'Engineering')
  .count

# Pagination
page_1 = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')
  .paginate(1, 20)  # Page 1, 20 per page
  .all
```

**Step 5: Update Extension Data**
```ruby
# Update using model method
employee.set_extension_data('Employee', {
  position: 'Lead Software Engineer',
  department: 'Engineering',
  salary: 150000.00
})

# Or using service (updates base + extension)
ExtendedModelService.update(
  employee,
  { first_name: 'John' },           # Base attributes
  {
    'Employee' => {                  # Extension attributes
      position: 'Staff Engineer',
      salary: 180000.00
    }
  }
)
```

**Step 6: Remove Extension**
```ruby
# Remove the Employee extension
employee.remove_extension('Employee')

# Or using service
ExtendedModelService.detach_extension(employee, 'Employee')
```

## Using with Other Models

The pattern is **completely generic**. Here's how to extend Products:

```ruby
# 1. Make Product extendable
class Product < ApplicationRecord
  include TenantScoped
  include Extendable  # ← Add this line

  belongs_to :customer
  validates :name, :sku, presence: true
end

# 2. Create a WarrantyProduct extension
warranty_entity = Entity.create!(
  name: 'WarrantyProduct',
  name_slug: 'warranty_product',
  customer: customer,
  property_schema: [
    { name: 'Warranty Period (months)', name_slug: 'warranty_period', type: 'Integer' },
    { name: 'Manufacturer', name_slug: 'manufacturer', type: 'String' }
  ].to_json
)

# 3. Create product with warranty extension
laptop = ExtendedModelService.create(
  Product,
  { name: 'Laptop Pro 15', sku: 'LAP-PRO-15', price: 1299.99 },
  'WarrantyProduct',
  { warranty_period: 24, manufacturer: 'TechCorp Inc.' },
  customer: customer
)

# 4. Query warranty products
products_with_24mo_warranty = Product.where_extension('WarrantyProduct', 'warranty_period', 24)
```

## View Helpers

**In Controllers:**
```ruby
class EmployeesController < ApplicationController
  def index
    @employees = ExtendedModelQueryBuilder.new(User, customer: current_customer)
      .of_type('Employee')
      .with_extensions
      .order(:created_at, :desc)
      .all

    @stats = ExtendedModelService.extension_stats(User, customer: current_customer)
  end

  def show
    @employee = User.of_extension_type('Employee').find(params[:id])
    @employee_data = @employee.extension_data('Employee')
  end
end
```

**In Views:**
```erb
<%# Show extension badges %>
<%= extension_badges(@employee) %>
<%# => Displays: Employee %>

<%# Render extension attributes %>
<%= render_extension_attributes(@employee, 'Employee') %>
<%# => Displays formatted definition list of all Employee attributes %>

<%# Show extension stats %>
<%= extension_stats_summary(User, current_customer) %>
<%# => Displays: Employee: 45, Contractor: 12 %>

<%# Access extension data manually %>
<% employee_data = @employee.extension_data('Employee') %>
<div>
  <strong>Position:</strong> <%= employee_data['position'] %>
  <strong>Department:</strong> <%= employee_data['department'] %>
  <strong>Salary:</strong> <%= number_to_currency(employee_data['salary']) %>
</div>
```

## Database Query Performance

The pattern uses efficient queries with proper indexing:

```sql
-- Find all employees in Engineering department
SELECT DISTINCT users.*
FROM users
INNER JOIN extended_model_entries ON extended_model_entries.extendable_id = users.id
  AND extended_model_entries.extendable_type = 'User'
INNER JOIN entity_entries ON entity_entries.id = extended_model_entries.entity_entry_id
WHERE extended_model_entries.entity_id = 5
  AND entity_entries.property_data->>'department' = 'Engineering'
  AND users.customer_id = 1;

-- Indexes used:
-- 1. idx_extended_model_entries_lookup (extendable_type, extendable_id, entity_id)
-- 2. idx_extended_model_entries_customer_entity (customer_id, entity_id)
-- 3. Index on users.customer_id
```

## Key Design Decisions

1. **Composition over Inheritance**: Uses polymorphic associations instead of STI
2. **Leverages Existing System**: Reuses Entity/EntityEntry infrastructure
3. **Non-Invasive**: No changes to existing model tables
4. **Type-Safe**: Validations through Entity schemas
5. **Query-Friendly**: JSONB with proper indexing allows efficient queries
6. **Multi-Tenant**: Customer isolation at every level
7. **Caching**: Built-in Rails caching for extension data
8. **Transaction Safety**: All create/update operations wrapped in transactions

## Benefits

- ✅ **Generic & Reusable** - Works with ANY model
- ✅ **Zero Schema Changes** - No migrations needed for new extensions
- ✅ **Dynamic** - Extensions defined at runtime by customers
- ✅ **Type-Safe** - Validation through Entity schemas
- ✅ **Query-Friendly** - Full support for filtering/searching
- ✅ **Multi-Tenant** - Built-in isolation
- ✅ **Testable** - All components fully tested
- ✅ **Developer-Friendly** - Multiple interfaces (model, service, query builder)
- ✅ **Production-Ready** - Follows Rails best practices

## Testing

See comprehensive test examples in `docs/EXTENSIBILITY_EXAMPLES.md` covering:
- Model specs
- Service specs
- Controller integration tests
- Factory patterns
