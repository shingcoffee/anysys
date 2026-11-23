# How the Generic Model Extensibility Pattern Works

## The Problem

In a multi-tenant SaaS application, different customers often need different attributes for the same type of record. For example:

- **Customer A** wants Users with fields: `position`, `department`, `salary` (Employees)
- **Customer B** wants Users with fields: `hourly_rate`, `contract_end_date` (Contractors)
- **Customer C** wants Users with fields: `badge_number`, `clearance_level` (Security Personnel)

Traditional solutions:
- ❌ **Add columns to `users` table** - Table becomes bloated, 90% of fields are NULL
- ❌ **Single Table Inheritance (STI)** - Creates rigid class hierarchies, hard to maintain
- ❌ **Separate tables** (employees, contractors, etc.) - Duplication, complex queries
- ❌ **JSON column on users** - No structure, no validation, no queryability

## Our Solution: Composition + Polymorphism

Instead of modifying the `users` table, we use a **polymorphic join table** that links any base model to dynamic extension data.

### The Architecture (Visual)

```
User Record                ExtendedModelEntry           Entity + EntityEntry
(base data)                (the link)                   (extension data + schema)

┌─────────────┐           ┌──────────────────┐         ┌────────────────────┐
│ id: 123     │           │ extendable_type: │         │ Entity:            │
│ first_name: │◄──────────│   "User"         │────────►│  name: "Employee"  │
│ last_name:  │           │ extendable_id:   │         │  schema: {...}     │
│ email:      │           │   123            │         └────────────────────┘
│ customer_id:│           │ entity_id: 5     │                ▲
└─────────────┘           │ entity_entry_id: │                │
                          │   789            │                │
  users table             └──────────────────┘                │
                                    │                          │
                          extended_model_entries               │
                                    │                          │
                                    ▼                          │
                          ┌──────────────────┐                │
                          │ EntityEntry:     │                │
                          │  id: 789         │────────────────┘
                          │  entity_id: 5    │
                          │  property_data:  │
                          │   {              │
                          │     position: "Developer",
                          │     department: "Engineering",
                          │     salary: 120000
                          │   }              │
                          └──────────────────┘

                            entity_entries table
```

## How It Works Step-by-Step

### 1. Make a Model Extensible

Add **one line** to any model:

```ruby
class User < ApplicationRecord
  include Extendable  # ← This single line enables extensibility
end
```

This adds:
- Polymorphic `has_many :extended_model_entries`
- Methods: `extension_data()`, `set_extension_data()`, `has_extension?()`
- Class methods: `where_extension()`, `of_extension_type()`
- Scopes: `with_extension()`, `with_extensions`, `without_extensions`

### 2. Define an Extension Schema

Create an Entity that defines what fields the extension has:

```ruby
employee_entity = Entity.create!(
  name: 'Employee',
  customer: customer,
  property_schema: [
    { name: 'Position', name_slug: 'position', type: 'String', validators: ['presence'] },
    { name: 'Department', name_slug: 'department', type: 'String' },
    { name: 'Salary', name_slug: 'salary', type: 'Float' }
  ].to_json
)
```

This is stored in the `entities` table - **no migration needed**.

### 3. Create a Record with Extension

```ruby
employee = ExtendedModelService.create(
  User,
  { first_name: 'John', last_name: 'Doe', email: 'john@example.com' },  # Base attrs
  'Employee',                                                             # Extension type
  { position: 'Developer', department: 'Engineering', salary: 120000 },  # Extension attrs
  customer: customer
)
```

This creates **three database records** in a transaction:

1. **User record** in `users` table
   ```
   id: 123
   first_name: "John"
   last_name: "Doe"
   email: "john@example.com"
   customer_id: 1
   ```

2. **EntityEntry record** in `entity_entries` table (stores the extension data)
   ```
   id: 789
   entity_id: 5  (references Employee entity)
   customer_id: 1
   property_data: { "position": "Developer", "department": "Engineering", "salary": 120000 }
   ```

3. **ExtendedModelEntry record** in `extended_model_entries` table (links them)
   ```
   id: 456
   extendable_type: "User"
   extendable_id: 123  (references user record)
   entity_id: 5        (references Employee entity schema)
   entity_entry_id: 789 (references actual data)
   customer_id: 1
   ```

### 4. Access Extension Data

```ruby
# Get extension data
employee.extension_data('Employee')
# => { "position" => "Developer", "department" => "Engineering", "salary" => 120000.0 }

# Check if has extension
employee.has_extension?('Employee')  # => true

# Get merged data (base + extension)
employee.full_attributes('Employee')
# => { "first_name" => "John", "last_name" => "Doe", ..., "position" => "Developer", ... }
```

Behind the scenes, this runs:
```sql
SELECT entity_entries.property_data
FROM entity_entries
INNER JOIN extended_model_entries ON extended_model_entries.entity_entry_id = entity_entries.id
WHERE extended_model_entries.extendable_type = 'User'
  AND extended_model_entries.extendable_id = 123
  AND extended_model_entries.entity_id = 5;
```

### 5. Query by Extension Attributes

```ruby
# Find all employees in Engineering department
engineers = User.where_extension('Employee', 'department', 'Engineering')

# Complex query
senior_engineers = ExtendedModelQueryBuilder.new(User, customer: customer)
  .of_type('Employee')
  .where_extension('Employee', 'department', 'Engineering')
  .where_extension('Employee', 'position', 'Senior Developer')
  .where(status: 'active')
  .all
```

This generates:
```sql
SELECT DISTINCT users.*
FROM users
INNER JOIN extended_model_entries ON extended_model_entries.extendable_id = users.id
  AND extended_model_entries.extendable_type = 'User'
INNER JOIN entity_entries ON entity_entries.id = extended_model_entries.entity_entry_id
WHERE extended_model_entries.entity_id = 5
  AND entity_entries.property_data->>'department' = 'Engineering'
  AND entity_entries.property_data->>'position' = 'Senior Developer'
  AND users.status = 0
  AND users.customer_id = 1;
```

## Why This Works Well

### 1. **No Schema Changes**
- Base table (`users`) never changes
- Add new extension types without migrations
- Each customer can have different extensions

### 2. **Type-Safe**
- Entity defines the schema (field types, validators)
- EntityEntry validates data against schema
- Validation happens before saving

### 3. **Query-Friendly**
- JSONB column with proper indexing
- Can filter by extension attributes efficiently
- Supports complex queries with joins

### 4. **Multi-Tenant Isolation**
- Every table has `customer_id`
- Extensions are tenant-specific
- No data leakage between tenants

### 5. **Truly Generic**
- Works with ANY model: Users, Products, Orders, etc.
- Same code, same pattern, same interface
- Just add `include Extendable` to any model

## Real Database Example

Let's create 2 users - one Employee, one Contractor:

```ruby
# Create Employee entity
employee_entity = Entity.create!(
  name: 'Employee',
  customer: customer,
  property_schema: [
    { name: 'Position', name_slug: 'position', type: 'String' },
    { name: 'Department', name_slug: 'department', type: 'String' }
  ].to_json
)

# Create Contractor entity
contractor_entity = Entity.create!(
  name: 'Contractor',
  customer: customer,
  property_schema: [
    { name: 'Hourly Rate', name_slug: 'hourly_rate', type: 'Float' },
    { name: 'Contract End Date', name_slug: 'contract_end_date', type: 'String' }
  ].to_json
)

# Create employee user
john = User.create_with_extension(
  { first_name: 'John', last_name: 'Doe', email: 'john@example.com', customer: customer },
  'Employee',
  { position: 'Developer', department: 'Engineering' }
)

# Create contractor user
jane = User.create_with_extension(
  { first_name: 'Jane', last_name: 'Smith', email: 'jane@example.com', customer: customer },
  'Contractor',
  { hourly_rate: 150.0, contract_end_date: '2024-12-31' }
)
```

### Database State:

**users table:**
```
id  | first_name | last_name | email                 | customer_id
----+------------+-----------+-----------------------+------------
123 | John       | Doe       | john@example.com      | 1
124 | Jane       | Smith     | jane@example.com      | 1
```

**entities table:**
```
id | name       | customer_id | property_schema
---+------------+-------------+----------------------------------
5  | Employee   | 1           | [{"name":"Position",...},...]
6  | Contractor | 1           | [{"name":"Hourly Rate",...},...]
```

**entity_entries table:**
```
id  | entity_id | customer_id | property_data
----+-----------+-------------+--------------------------------------------------
789 | 5         | 1           | {"position":"Developer","department":"Engineering"}
790 | 6         | 1           | {"hourly_rate":150.0,"contract_end_date":"2024-12-31"}
```

**extended_model_entries table:**
```
id  | extendable_type | extendable_id | entity_id | entity_entry_id | customer_id
----+-----------------+---------------+-----------+-----------------+------------
456 | User            | 123           | 5         | 789             | 1
457 | User            | 124           | 6         | 790             | 1
```

Now we can query:

```ruby
# Get all employees
User.of_extension_type('Employee')  # Returns: [john]

# Get all contractors
User.of_extension_type('Contractor')  # Returns: [jane]

# Get employees in Engineering
User.where_extension('Employee', 'department', 'Engineering')  # Returns: [john]

# Get contractors with rate > 100
User.joins(extended_model_entries: :entity_entry)
  .where(extended_model_entries: { entity_id: contractor_entity.id })
  .where("entity_entries.property_data->>'hourly_rate' > ?", '100')
  # Returns: [jane]
```

## The Components

### Core Files

1. **`app/models/concerns/extendable.rb`** (312 lines)
   - The heart of the system
   - Adds polymorphic associations and methods to any model
   - Provides scopes, instance methods, class methods

2. **`app/models/extended_model_entry.rb`** (82 lines)
   - Polymorphic join model
   - Links base models to Entity schemas and EntityEntry data
   - Enforces uniqueness constraints

3. **`db/migrate/XXXXXX_create_extended_model_entries.rb`**
   - Creates the polymorphic join table
   - Adds composite indexes for performance

4. **`app/services/extended_model_service.rb`** (218 lines)
   - High-level API for working with extensions
   - Methods: create, update, attach, detach, query, stats

5. **`app/services/extended_model_query_builder.rb`** (239 lines)
   - Fluent query builder for complex queries
   - Chainable methods, eager loading, pagination

6. **`app/helpers/extended_model_helper.rb`** (180 lines)
   - View helpers for rendering extension data
   - Badges, stats, attribute formatting

## Key Design Decisions

### Why Polymorphic?
- Allows ANY model to be extended
- No need for model-specific join tables
- Single implementation works everywhere

### Why Reuse Entity/EntityEntry?
- Already handles dynamic schemas and validation
- No duplication of schema management logic
- Consistent validation across the app

### Why Service Layer?
- Encapsulates complex multi-step operations
- Ensures transactional consistency
- Provides clean API for controllers

### Why Query Builder?
- Complex queries need multiple joins
- Fluent interface is readable and chainable
- Handles N+1 queries with eager loading

### Why JSONB?
- Flexible storage for dynamic attributes
- Indexable and queryable with PostgreSQL
- No schema changes needed for new fields

## Performance Considerations

### Indexing Strategy
```ruby
# Composite index for lookups
add_index :extended_model_entries,
  [:extendable_type, :extendable_id, :entity_id],
  unique: true

# Customer + entity for listing
add_index :extended_model_entries,
  [:customer_id, :entity_id]

# Polymorphic lookups
add_index :extended_model_entries,
  [:extendable_type, :extendable_id]
```

### Eager Loading
```ruby
# Without eager loading (N+1 queries)
users = User.of_extension_type('Employee')
users.each { |u| puts u.extension_data('Employee') }  # N queries!

# With eager loading (2 queries total)
users = User.of_extension_type('Employee').with_extensions
users.each { |u| puts u.extension_data('Employee') }  # Uses preloaded data
```

### Caching
```ruby
# Extension data is cached automatically
def all_extension_data
  Rails.cache.fetch("#{cache_key_with_version}/all_extensions", expires_in: 1.hour) do
    # ... fetch from database
  end
end
```

## Testing

The pattern is fully tested with RSpec:

```ruby
# Model specs
RSpec.describe Extendable do
  it 'creates extension entry' do
    expect {
      user.set_extension_data(entity, { key: 'value' })
    }.to change(ExtendedModelEntry, :count).by(1)
  end

  it 'queries by extension attribute' do
    users = User.where_extension(entity, 'department', 'Engineering')
    expect(users.count).to eq(2)
  end
end

# Service specs
RSpec.describe ExtendedModelService do
  it 'creates record with extension' do
    user = described_class.create(
      User,
      { first_name: 'John' },
      'Employee',
      { position: 'Developer' },
      customer: customer
    )

    expect(user).to be_persisted
    expect(user.extension_data('Employee')['position']).to eq('Developer')
  end
end
```

## Summary

The generic extensibility pattern allows **any model** to be extended with **custom attributes** without **schema changes**, using:

1. **Polymorphic associations** (works with any model)
2. **Existing Entity/EntityEntry system** (reuses schema validation)
3. **Service layer** (clean API, transactional safety)
4. **Query builder** (complex queries, eager loading)
5. **View helpers** (easy rendering)

Just add `include Extendable` to any model and it instantly gains the ability to have customer-specific extensions with full querying support!
