# Entity Associations Feature

## Overview

This feature enables entities to establish many-to-many relationships with other entities through automatically generated junction entities. This is particularly useful for scenarios like students enrolling in classes with scores, products having multiple categories with priorities, etc.

## Architecture

### Database Schema

```ruby
# entities table
- id
- name
- name_slug
- customer_id
- property_schema (JSON)
- associations (JSON)     # NEW FIELD
- extendable_model
- ...
```

### Association Data Structure

```json
{
  "associations": [
    {
      "target_entity_id": 3,
      "target_entity_name": "Class",
      "junction_entity_id": 5,
      "junction_entity_name": "ClassStudent",
      "additional_attributes": [
        {
          "name": "Score",
          "name_slug": "score",
          "type": "Float",
          "html_type": "number",
          "validators": []
        },
        {
          "name": "Enrollment Date",
          "name_slug": "enrollment_date",
          "type": "String",
          "html_type": "date",
          "validators": []
        }
      ]
    }
  ]
}
```

## How It Works

### 1. Creating an Association

When you create or edit an entity and add an association:

1. **User selects target entity** - e.g., "Student" entity associates with "Class" entity
2. **User defines additional attributes** - e.g., score, enrollment_date
3. **On save**, the system:
   - Saves the association configuration to the entity's `associations` JSON field
   - Calls `entity.sync_junction_entities!` to create junction entity

### 2. Junction Entity Creation

The `sync_junction_entities!` method:

```ruby
def sync_junction_entities!
  return unless has_associations?

  associations_list.each do |assoc|
    sync_single_junction_entity(assoc)
  end
end
```

For each association, it:

1. **Generates junction entity name** - Alphabetically sorts entity names (e.g., "ClassStudent")
2. **Finds or creates junction entity** - Using name_slug as unique identifier
3. **Builds property schema**:
   - Two EntityReference fields (one for each entity)
   - Additional attributes from association config
4. **Saves junction entity** - Creates if new, updates if exists
5. **Updates association** - Stores junction_entity_id back to source entity

### 3. Junction Entity Structure

For Student ↔ Class association with score:

```ruby
Junction Entity: "ClassStudent"

property_schema: [
  {
    "name": "Student",
    "name_slug": "student",
    "type": "EntityReference",
    "html_type": "",
    "entity_id": "1",  # References Student entity
    "validators": [{"type": "presence"}]
  },
  {
    "name": "Class",
    "name_slug": "class",
    "type": "EntityReference",
    "html_type": "",
    "entity_id": "2",  # References Class entity
    "validators": [{"type": "presence"}]
  },
  {
    "name": "Score",
    "name_slug": "score",
    "type": "Float",
    "html_type": "number",
    "validators": []
  }
]
```

## Usage Example

### Step 1: Create Base Entities

```ruby
# Create Student entity
student = Entity.create!(
  name: "Student",
  customer_id: customer_id,
  element_type: "custom",
  property_schema: [
    { name: "Name", name_slug: "name", type: "String", html_type: "text" },
    { name: "Email", name_slug: "email", type: "String", html_type: "email" }
  ]
)

# Create Class entity
class_entity = Entity.create!(
  name: "Class",
  customer_id: customer_id,
  element_type: "custom",
  property_schema: [
    { name: "Class Name", name_slug: "name", type: "String", html_type: "text" },
    { name: "Code", name_slug: "code", type: "String", html_type: "text" }
  ]
)
```

### Step 2: Create Association (via UI or programmatically)

```ruby
student.associations_json = [
  {
    target_entity_id: class_entity.id,
    target_entity_name: class_entity.name,
    additional_attributes: [
      {
        name: "Score",
        name_slug: "score",
        type: "Float",
        html_type: "number",
        validators: []
      },
      {
        name: "Enrollment Date",
        name_slug: "enrollment_date",
        type: "String",
        html_type: "date",
        validators: []
      }
    ]
  }
]

student.save!
student.sync_junction_entities!  # Creates "ClassStudent" junction entity
```

### Step 3: Create Records

```ruby
# Create student entry
john = EntityEntry.create!(
  entity: student,
  customer_id: customer_id,
  data_json: {
    name: "John Doe",
    email: "john@example.com"
  }
)

# Create class entry
math = EntityEntry.create!(
  entity: class_entity,
  customer_id: customer_id,
  data_json: {
    name: "Mathematics",
    code: "MATH101"
  }
)

# Create enrollment (junction entry)
junction_entity = Entity.find_by(name_slug: "class_student")

enrollment = EntityEntry.create!(
  entity: junction_entity,
  customer_id: customer_id,
  data_json: {
    student: john.id,
    class: math.id,
    score: 85.5,
    enrollment_date: "2024-01-15"
  }
)
```

### Step 4: Query Data

```ruby
# Get all classes for a student
enrollments = EntityEntry.where(
  entity: junction_entity,
  customer_id: customer_id
).where("data_json->>'student' = ?", john.id.to_s)

enrollments.each do |enrollment|
  class_id = enrollment.data_json['class']
  score = enrollment.data_json['score']
  class_entry = EntityEntry.find(class_id)

  puts "Class: #{class_entry.data_json['name']}, Score: #{score}"
end
```

## UI Workflow

### Creating an Association

1. Navigate to entity edit page
2. Scroll to "Entity Associations" section
3. Click "+ Add Association" button
4. **Association Modal opens**:
   - Select target entity from dropdown
   - (Optional) Add additional attributes:
     - Click "+ Add Attribute"
     - Enter name, type, and HTML type
     - Repeat for each attribute
   - Click "Add Association"
5. Association appears in table with status "Will be created on save"
6. Click "Save Changes"
7. Junction entity is created automatically
8. Association table updates showing junction entity name

### Managing Associations

- **View**: See all associations in the associations table
- **Remove**: Click trash icon to remove an association
- **Edit**: Remove and re-add (editing in place not yet implemented)

## Implementation Details

### Entity Model

**New Methods:**

- `associations_list` - Returns array of association configs
- `has_associations?` - Check if entity has associations
- `sync_junction_entities!` - Create/update junction entities
- `sync_single_junction_entity(assoc)` - Handle single association
- `generate_junction_name(name1, name2)` - Generate junction entity name

### Controller

**Updated Actions:**

- `create` - Calls `sync_junction_entities!` after save
- `update` - Calls `sync_junction_entities!` after save
- `entity_params` - Permits `:associations`

### JavaScript Controller

**New Targets:**

- `associationsContainer`, `associationsTable`, `associationsEmptyState`
- `associationsSchema` (hidden field)
- `associationModal`, `associationTargetEntity`
- `associationAttributesContainer`, `associationAttributesEmptyState`

**New Methods:**

- `openAssociationModal()` - Open modal and load entities
- `closeAssociationModal()` - Close modal and reset
- `saveAssociation()` - Collect data and add to list
- `addAssociationAttribute()` - Add attribute field in modal
- `removeAssociation(event)` - Remove association from list
- `syncAssociationsSchema()` - Sync to hidden field
- `collectAllAssociations()` - Extract associations from DOM

### View Templates

**New Partials:**

- `_associations_table.html.erb` - Display associations
- `_association_modal.html.erb` - Modal for adding associations

**Updated Files:**

- `_form.html.erb` - Added associations section and hidden field

## Benefits

✅ **No New Models** - Uses existing Entity/EntityEntry structure
✅ **Automatic Management** - Junction entities created/updated automatically
✅ **Flexible** - Supports arbitrary additional attributes
✅ **Consistent** - Uses same patterns as regular entities
✅ **Multi-tenant Safe** - Customer scoping maintained
✅ **User-Friendly** - Simple UI for complex relationships

## Limitations

1. **Junction entity name conflicts** - If two different associations would generate the same junction name, there will be conflicts
2. **No cascading deletes** - Deleting an entity doesn't automatically clean up junction entities
3. **Association editing** - Must remove and re-add to modify (no in-place editing yet)
4. **Validation** - No validation of target entity existence before save

## Future Enhancements

- [ ] Edit associations in place
- [ ] Cascade delete options for junction entities
- [ ] Validation of target entity existence
- [ ] Custom junction entity naming
- [ ] Association constraints (uniqueness, etc.)
- [ ] Visual relationship diagram
- [ ] Bulk association management
- [ ] Association templates

## Testing

To test the feature:

1. Create two entities (e.g., Student and Class)
2. Edit one entity
3. Add association to the other entity
4. Add additional attributes (e.g., score, date)
5. Save entity
6. Verify junction entity was created (check entities list)
7. Create entity entries for both entities
8. Create junction entry linking them
9. Query and verify data

## Troubleshooting

**Junction entity not created:**
- Check server logs for errors
- Verify target entity exists
- Ensure associations JSON is valid

**Associations not saving:**
- Check that JavaScript controller is loaded
- Verify `syncAssociationsSchema()` is being called
- Check browser console for errors

**Can't find junction entries:**
- Verify junction entity was created
- Check junction entity name (alphabetically sorted)
- Ensure customer_id is correct in queries
