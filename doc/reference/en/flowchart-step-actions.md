---
title: "Flowchart step actions"
summary: "Catalog reference for the 78 process step actions: category, label, one-line description, every configuration field with its role, requirement and default, and the ctx keys each action writes."
---

## Summary

A process box on the flowchart canvas holds exactly one step action. The catalog of step actions is not hand-written: each action is a generator class under `app/services/code_generators/element_types/process/<category>/` that declares its fields once in `config_schema ported: true do … end`, and `CodeGenerators::ActionCatalog.export(locale:)` turns those declarations plus the `flowchart_actions.*` translations into the JSON the editor, the assistant palette and this page read. The catalog has 79 actions in 15 categories.

The tables below were generated from `ActionCatalog.export(locale: "en")` (catalog digest `797261f4fec9c53913c96f6275f7dbf848c7fc9c12f6f32d5fafb81e1109d286`). When a generator or its locale keys change, regenerate them from the export rather than editing a row by hand. How the schema DSL, the export and the emission helpers work is [Code generators](code-generators); how the step form renders these fields is [Flowchart builder](flowchart-builder); the runtime helpers the emitted code calls are [Flowchart runtime](flowchart-runtime).

## Flow

```text
app/services/code_generators/element_types/process/<category>/<action>_generator.rb
        |  generator_metadata (category, presentation icon / color / single_use / privileged)
        |  config_schema ported: true  (roles, requires, validate, capabilities)
        v
config/locales/flowchart_actions_<area>.{en,zh-CN}.yml
        |  flowchart_actions.<action>.{label, description, fields.<f>.{label, help, placeholder, options}}
        v
CodeGenerators::ActionCatalog.export(locale:)
        |  categories (CATEGORY_ORDER) + actions + digest
        +--> flowchart editor   data-flowchart-canvas-action-catalog-value
        +--> assistant palette   FlowchartDefinitions::Assistant::SchemaGenerator
        +--> this page           generated tables
```

## Implementation

### Reading the tables

Each action lists its catalog label, its key (the value stored as `step.action`), the catalog description, and one row per configuration field:

- **Field** is the key stored in `step.config`.
- **Role** is the `config_schema` role. It decides validation, the editor control and the Ruby that `read(:field)` emits: `input` (ctx path such as `params.email`, with a variable picker), `output` (ctx key the step writes), `expression` (one safe Ruby expression), `literal`, `template` (Liquid), `enum`, `flag` (JSON boolean), `integer`, `decimal`, `list`, `mapping` (`[{ "key", "value" }]` rows), `conditions` (a Decision-style condition group), `entity_attribute` (an attribute slug of the bound entity), `reference` (a record or key from a registered reference source) and `localized_text` (`{ "en", "zh-CN" }`, `en` required).
- **Required / default** is `required` for fields declared `required: true`, and the declared default when there is one. A hidden field (its *shown when* rule does not match) is neither validated nor read; the generator sees its default.
- **Notes** list the conditional rules (*required when*, *shown when*), the reference source, the item / key / value roles of lists and mappings, the enum values (optional enums also get an empty "None" option in the editor) and numeric ranges.

The advanced HTTP fields that `transport_retry`, `timeouts` and `circuit_breaker_option` add (`retryOnTransportError`, `retryAttempts`, `connectTimeout`, `readTimeout`, `circuitBreaker`, `breakerName`, `failureThreshold`, `resetTimeoutSeconds`) are not repeated per action; the action's last line names which of them it has. Their ranges and rules are on [Code generators](code-generators).

**Writes** lists the ctx keys a successful step writes: every `output` field (the stored value overrides the default) plus the standard keys the action is documented to write (`contract`, `submission_outcome`). Every action can also append to `ctx[:errors]` and `ctx[:error_details]` through `FlowchartRuntime::Step.fail` when it fails; that is not repeated per action.

### Records (`model`)

#### Aggregate Query (`aggregate_query`)

Run aggregate queries (sum, avg, etc.)

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `aggregations` | Aggregations | `mapping` | optional | key `entity_attribute` → value `literal` |
| `aggregateFunction` | Aggregate Function | `enum` | default `sum` | `sum` / `average` / `minimum` / `maximum` / `count` |
| `aggregateField` | Aggregate Field | `entity_attribute` | default `amount` |  |
| `groupBy` | Group By | `literal` | optional |  |
| `groupByFields` | Group By Fields | `list` | optional | items `entity_attribute` |
| `having` | Having | `literal` | optional |  |
| `resultFormat` | Result Format | `enum` | default `scalar` | `scalar` / `hash` |
| `conditions` | Conditions | `conditions` | default `{"type":"group","joins":[],"conditions":[]}` |  |
| `resultVar` | Save result as | `output` | default `aggregates` |  |

Writes: `resultVar` (default `aggregates`).

#### Batch Operation (`batch_operation`)

Perform batch operations on multiple records

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `operationType` | Operation Type | `enum` | default `find_each` | `find_each` / `in_batches` / `each_batch` / `update_all` / `destroy_all` |
| `batchSize` | Batch Size | `integer` | default `1000` | range 1–10000 |
| `stepBody` | Step Body | `expression` | optional | shown when `operationType` = `find_each` / `in_batches` / `each_batch` |
| `fieldAssignments` | Field Assignments | `mapping` | optional | shown when `operationType` = `update_all`; key `entity_attribute` → value `expression` |
| `conditions` | Conditions | `conditions` | default `{"type":"group","joins":[],"conditions":[]}` |  |
| `errorCollection` | Collect errors | `flag` | default `false` |  |
| `progressVar` | Save progress as | `output` | default `progress` |  |

Writes: `progressVar` (default `progress`).

#### Bulk Import (`bulk_import`)

Bulk import records

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `onDuplicateKey` | On Duplicate Key | `enum` | default `skip` | `update` / `skip` |
| `uniqueBy` | Unique By | `list` | optional | items `entity_attribute` |
| `resultVar` | Save result as | `output` | default `import_result` |  |

Writes: `resultVar` (default `import_result`).

#### Clone record (`clone_model`)

Duplicate a loaded record of the bound entity.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `modelVariable` | Record | `input` | default `model` |  |
| `resultVar` | Save result as | `output` | default `clone` |  |

Writes: `resultVar` (default `clone`).

#### Count Records (`count_records`)

Count matching records

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `conditions` | Conditions | `conditions` | default `{"type":"group","joins":[],"conditions":[]}` |  |
| `resultAs` | Result as | `enum` | default `count` | `count` / `exists` / `absent` |
| `distinct` | Distinct | `flag` | default `false` |  |
| `distinctField` | Distinct Field | `entity_attribute` | optional | shown when `distinct` = `true` |
| `groupBy` | Group By | `entity_attribute` | optional |  |
| `resultVar` | Save result as | `output` | default `count` |  |

Writes: `resultVar` (default `count`).

#### Destroy record (`destroy_model`)

Delete a loaded record, or archive it by setting a date-time attribute.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `modelVariable` | Record | `input` | default `model` |  |
| `mode` | Mode | `enum` | default `delete` | `delete` / `archive` |
| `archiveField` | Archive field | `entity_attribute` | optional | required when `mode` = `archive` |
| `archivedByField` | Archived-by field | `entity_attribute` | optional | shown when `mode` = `archive` |

Writes: no ctx key; the step returns success or failure.

#### Find record (`find_model`)

Load one record of the bound entity by id, by an attribute, or the signed-in member's own person record (`findBy: current_person`, version `5.1.0`).

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `findBy` | Find by | `enum` | default `id` | `id` / `attribute` / `current_person` (`current_person` is "The signed-in member's own record") |
| `idSource` | Id | `input` | default `params.id` | shown when `findBy` = `id` |
| `findField` | Attribute | `entity_attribute` | optional | required when `findBy` = `attribute` |
| `findValue` | Value | `input` | optional | required when `findBy` = `attribute` |
| `resultVar` | Save result as | `output` | default `model` |  |

`findBy: current_person` emits `FlowchartRuntime::Entries.find_current_person(ctx)`. It reads only `ctx[:current_person_ids]`, never `params[:id]`. The existing `fail_with(:record_not_found, …)` covers an anonymous viewer, a member with no link, a bound entity that is not a person entity, and a missing entry. Flowchart record queries are never row-scoped; this lookup is trusted context, not `People::Ownership.scope`. See [Flowchart runtime](flowchart-runtime) and [Person linking](person-linking).

Writes: `resultVar` (default `model`).

#### Load current user (`load_current_user`)

Load the signed-in user for this customer as a read-only hash, including `person_entries` (`{ "<person entity id>" => entry_id }`).

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `resultVar` | Save result as | `output` | default `current_user` |  |
| `required` | Required | `flag` | default `true` |  |

Writes: `resultVar` (default `current_user`).

#### New record (`new_model`)

Create a new unsaved record of the bound entity.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `resultVar` | Save result as | `output` | default `model` |  |

Writes: `resultVar` (default `model`).

#### Sequence number (`next_sequence_number`)

Allocate the next tenant-scoped sequence number

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sequenceName` | Sequence name | `literal` | required |  |
| `prefix` | Prefix | `literal` | optional |  |
| `padding` | Padding | `integer` | default `6` | range 1–12 |
| `resetEvery` | Reset every | `enum` | default `never` | `never` / `year` / `month` |
| `resultVar` | Save result as | `output` | default `sequence_number` |  |

Writes: `resultVar` (default `sequence_number`).

#### Query Models (`query_models`)

Complex model queries

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `conditions` | Conditions | `conditions` | default `{"type":"group","joins":[],"conditions":[]}` |  |
| `select` | Select | `list` | optional | items `entity_attribute` |
| `returns` | Returns | `enum` | default `records` | `records` / `values` |
| `pageVariable` | Page Variable | `input` | default `page` |  |
| `pageSize` | Page Size | `integer` | optional | range 1–200 |
| `limit` | Limit | `integer` | optional | range 1–1000 |
| `orderBy` | Order By | `literal` | optional |  |
| `orderDirection` | Order Direction | `enum` | default `asc` | `asc` / `desc` |
| `distinct` | Distinct | `flag` | default `false` |  |
| `resultVar` | Save result as | `output` | default `models` |  |
| `paginationVar` | Save pagination as | `output` | default `pagination` |  |

Writes: `resultVar` (default `models`), `paginationVar` (default `pagination`).

#### Related record (`related_record`)

Find, create, or update a record linked through an association.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `association` | Association | `reference` | required | source `entity_associations` |
| `operation` | Operation | `enum` | default `find` | `find` / `create` / `update` |
| `modelVariable` | Record | `input` | default `model` |  |
| `conditions` | Conditions | `conditions` | default `{"type":"group","joins":[],"conditions":[]}` | shown when `operation` = `find` |
| `assignments` | Assignments | `mapping` | optional | shown when `operation` = `create` / `update`; key `entity_attribute` → value `expression` |
| `resultVar` | Save result as | `output` | default `related_record` |  |

Writes: `resultVar` (default `related_record`).

#### Save record (`save_model`)

Persist the Reform contract's model through the bound entity.

No configuration fields.

Writes: no ctx key; the step returns success or failure.

#### Set record fields (`set_record_fields`)

Write attributes on a loaded record without saving it.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `modelVariable` | Record | `input` | default `model` |  |
| `assignments` | Assignments | `mapping` | optional | key `entity_attribute` → value `expression` |

Writes: no ctx key; the step returns success or failure.

#### Update record (`update_model`)

Apply the contract or params to a loaded record and save it.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `modelVariable` | Record | `input` | default `model` |  |
| `changesVar` | Save changes as | `output` | optional |  |

Writes: `changesVar`.

#### Upsert record (`upsert_model`)

Find a matching record of the bound entity and update it, or create one.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `matchFields` | Match fields | `list` | required | items `entity_attribute` |
| `resultVar` | Save result as | `output` | default `model` |  |
| `createdVar` | Save created flag as | `output` | default `created` |  |

Writes: `resultVar` (default `model`), `createdVar` (default `created`).

### Validation (`validation`)

#### Build Contract (`build_contract`)

Build the Reform contract wrapping the primary entity model

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `contractClass` | Contract Class | `literal` | default `EntityEntryContract` |  |
| `modelVariable` | Model Variable | `input` | default `model` |  |

Writes: `ctx[:contract]`.

#### Fail with a business error (`fail_with_error`)

End the run on the failure track with a localized message

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `message` | Message | `localized_text` | required |  |
| `field` | Field | `literal` | optional |  |

Writes: `ctx[:errors]`, `ctx[:error_details]`.

#### Validate (`validate_contract`)

Validate the Reform contract against ctx[:params]

No configuration fields.

Writes: no ctx key; the step returns success or failure.

### Data (`data`)

#### Assign Value (`assign_value`)

Set a ctx variable

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `resultVar` | Save result as | `output` | default `assigned` |  |
| `valueType` | Value Type | `enum` | default `expression` | `string` / `integer` / `float` / `boolean` / `array` / `hash` / `expression` / `null` / `ctx_ref` / `random` / `first_present` |
| `valueExpression` | Value Expression | `expression` | optional | required when `valueType` = `expression` |
| `stringValue` | String Value | `literal` | optional | shown when `valueType` = `string` |
| `integerValue` | Integer Value | `integer` | default `0` | shown when `valueType` = `integer` |
| `floatValue` | Float Value | `decimal` | default `0.0` | shown when `valueType` = `float` |
| `booleanValue` | Boolean Value | `flag` | default `false` | shown when `valueType` = `boolean` |
| `arrayValue` | Array Value | `list` | optional | shown when `valueType` = `array`; items `literal` |
| `hashValue` | Hash Value | `mapping` | optional | shown when `valueType` = `hash`; key `literal` → value `literal` |
| `ctxRefVariable` | Ctx Ref Variable | `input` | optional | required when `valueType` = `ctx_ref` |
| `randomType` | Random Type | `enum` | default `uuid` | shown when `valueType` = `random`; `uuid` / `hex` / `int` / `float` |
| `randomLength` | Random Length | `integer` | default `0` | shown when `valueType` = `random`; range 0– |
| `candidates` | Candidates | `list` | optional | required when `valueType` = `first_present`; items `input` |
| `literalCandidates` | Literal Candidates | `list` | optional | shown when `valueType` = `first_present`; items `literal` |
| `predicate` | Predicate | `enum` | default `nil` | shown when `valueType` = `first_present`; `nil` / `blank` / `false_or_nil` |
| `blankDefinition` | Blank Definition | `enum` | default `nil` | shown when `valueType` = `first_present`; `nil` / `empty` / `whitespace` |

Writes: `resultVar` (default `assigned`).

#### Calculate (`calculate`)

Compute/aggregate values

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `operation` | Operation | `enum` | default `count` | `sum` / `count` / `avg` / `min` / `max` / `product` / `concat` / `custom` |
| `fieldName` | Field Name | `literal` | optional | shown when `operation` = `sum` / `avg` / `min` / `max` / `product` / `concat` |
| `customExpression` | Custom Expression | `expression` | optional | required when `operation` = `custom` |
| `resultVar` | Save result as | `output` | default `total` |  |
| `emptyCollectionBehavior` | Empty Collection Behavior | `enum` | default `zero` | `zero` / `nil` |
| `emptyCollectionDefault` | Empty Collection Default | `literal` | optional |  |
| `ignoreNils` | Ignore Nils | `flag` | default `true` |  |
| `nullFilter` | Null Filter | `flag` | default `false` |  |
| `precision` | Precision | `integer` | default `0` | range 0–12 |
| `roundingMode` | Rounding Mode | `enum` | default `half_up` | `half_up` / `half_even` / `floor` / `ceiling` |

Writes: `resultVar` (default `total`).

#### Collection Manipulate (`collection_manipulate`)

Map, pluck, group, sort, unique, chunk, flatten, or zip a collection

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `operation` | Operation | `enum` | default `map` | `map` / `pluck` / `group` / `sort` / `unique` / `chunk` / `flatten` / `zip` |
| `sourceVariable` | Source | `input` | optional | required when `operation` = `map` / `pluck` / `group` / `sort` / `unique` / `chunk` / `flatten` |
| `sources` | Sources | `list` | optional | required when `operation` = `zip`; items `input` |
| `resultVar` | Save result as | `output` | default `collection` |  |
| `fieldMappings` | Field Mappings | `mapping` | optional | required when `operation` = `map`; key `literal` → value `literal` |
| `keyFormat` | Key Format | `enum` | default `symbol` | shown when `operation` = `map`; `symbol` / `string` |
| `compactResult` | Compact Result | `flag` | default `false` | shown when `operation` = `map` |
| `preserveNilElements` | Preserve Nil Elements | `flag` | default `true` | shown when `operation` = `map` |
| `fields` | Fields | `mapping` | optional | required when `operation` = `pluck`; key `literal` → value `literal` |
| `flattenSingle` | Flatten Single Field | `flag` | default `false` | shown when `operation` = `pluck` |
| `includeSourceIndex` | Include Source Index | `flag` | default `false` | shown when `operation` = `pluck` |
| `groupField` | Group Field | `literal` | optional | shown when `operation` = `group` |
| `groupByExpression` | Group By Expression | `expression` | optional | shown when `operation` = `group` |
| `includeCount` | Include Count | `flag` | default `false` | shown when `operation` = `group` |
| `sortGroups` | Sort Groups | `enum` | default `none` | shown when `operation` = `group`; `none` / `key_asc` / `key_desc` / `count_asc` / `count_desc` |
| `sortField` | Sort Field | `literal` | optional | required when `operation` = `sort` |
| `sortDirection` | Sort Direction | `enum` | default `asc` | shown when `operation` = `sort`; `asc` / `desc` |
| `nullsFirst` | Nulls First | `flag` | default `false` | shown when `operation` = `sort` |
| `uniqField` | Unique Field | `literal` | optional | shown when `operation` = `unique` |
| `keepStrategy` | Keep Strategy | `enum` | default `first` | shown when `operation` = `unique`; `first` / `last` |
| `chunkMode` | Chunk Mode | `enum` | default `size` | shown when `operation` = `chunk`; `size` / `predicate` / `field` |
| `chunkSize` | Chunk Size | `integer` | default `100` | shown when `operation` = `chunk`; range 1– |
| `includeRemainder` | Include Remainder | `flag` | default `true` | shown when `operation` = `chunk` |
| `chunkPredicate` | Chunk Predicate | `expression` | optional | required when `chunkMode` = `predicate`; shown when `operation` = `chunk` |
| `chunkField` | Chunk Field | `literal` | optional | required when `chunkMode` = `field`; shown when `operation` = `chunk` |
| `depth` | Depth | `integer` | default `1` | shown when `operation` = `flatten`; range 0– |
| `removeNilElements` | Remove Nil Elements | `flag` | default `false` | shown when `operation` = `flatten` |
| `zipStrategy` | Zip Strategy | `enum` | default `shortest` | shown when `operation` = `zip`; `strict` / `longest` / `shortest` |
| `resultShape` | Result Shape | `enum` | default `tuples` | shown when `operation` = `zip`; `tuples` / `hashes` |
| `fillValue` | Fill Value | `expression` | optional | shown when `operation` = `zip` |

Writes: `resultVar` (default `collection`).

#### Compare Data (`compare_data`)

Compare two values

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Left Key | `input` | required |  |
| `otherVariable` | Right Key | `input` | required |  |
| `resultVar` | Save result as | `output` | default `diff` |  |
| `mode` | Mode | `enum` | default `keys` | `keys` / `values` / `deep` |
| `comparisonType` | Comparison Type | `enum` | default `equality` | `equality` / `deep_equal` / `schema_match` / `diff` |
| `ignoreKeys` | Ignore Keys | `list` | optional | items `literal` |
| `caseInsensitive` | Case Insensitive | `flag` | default `false` |  |
| `numericTolerance` | Numeric Tolerance | `decimal` | default `0` | range 0– |

Writes: `resultVar` (default `diff`).

#### Date/Time Calc (`date_time_calc`)

Date and time calculations

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `operation` | Operation | `enum` | default `now` | `add` / `subtract` / `difference` / `format` / `parse` / `now` / `convert_timezone` |
| `resultVar` | Save result as | `output` | default `datetime` |  |
| `sourceVariable` | Source Variable | `input` | optional | required when `operation` = `add` / `subtract` / `difference` / `format` / `parse` / `convert_timezone` |
| `endVariable` | End Variable | `input` | optional | required when `operation` = `difference` |
| `amount` | Amount | `integer` | default `1` | required when `operation` = `add` / `subtract`; range 0–10000 |
| `unit` | Unit | `enum` | default `days` | required when `operation` = `add` / `subtract`; `seconds` / `minutes` / `hours` / `days` / `weeks` / `months` / `years` |
| `formatString` | Format String | `literal` | default `%Y-%m-%d` | required when `operation` = `format` |
| `inputFormat` | Input Format | `literal` | optional |  |
| `outputFormat` | Output Format | `literal` | optional |  |
| `businessDays` | Business Days Only | `flag` | default `false` |  |
| `timezoneAware` | Timezone Aware | `flag` | default `false` |  |
| `timezone` | Timezone | `literal` | optional | shown when `timezoneAware` = `true` |
| `dstPolicy` | DST Policy | `enum` | default `preserve_wall` | `preserve_wall` / `preserve_utc` |
| `sourceTimezone` | Source Timezone | `literal` | default `UTC` |  |
| `targetTimezone` | Target Timezone | `literal` | optional | required when `operation` = `convert_timezone` |
| `preserveLocalTime` | Preserve Local Time | `flag` | default `false` |  |
| `dstBehavior` | DST Behavior | `enum` | default `prefer_later` | shown when `preserveLocalTime` = `true`; `raise_on_ambiguous` / `prefer_earlier` / `prefer_later` |

Writes: `resultVar` (default `datetime`).

#### Filter Collection (`filter_collection`)

Filter items in a collection

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `returns` | Returns | `enum` | default `items` | `items` / `split` / `first` / `last` / `index` / `count` / `any` / `all` / `none` |
| `resultVar` | Save result as | `output` | default `filtered` |  |
| `rejectedVar` | Save rejected as | `output` | default `rejected` | shown when `returns` = `split` |
| `filterMode` | Filter Mode | `enum` | default `single` | `single` / `multi` |
| `filterField` | Filter Field | `literal` | optional | required when `filterMode` = `single` |
| `filterOperator` | Filter Operator | `enum` | default `eq` | shown when `filterMode` = `single`; `eq` / `ne` / `gt` / `lt` / `gte` / `lte` / `includes` / `blank` / `present` |
| `filterValue` | Filter Value | `literal` | optional | shown when `filterMode` = `single` |
| `conditions` | Conditions | `list` | optional | required when `filterMode` = `multi` |
| `conditionOperator` | Condition Operator | `enum` | default `AND` | shown when `filterMode` = `multi`; `AND` / `OR` |
| `rejectMode` | Reject Mode | `flag` | default `false` |  |
| `nilHandling` | Nil Handling | `enum` | default `treat_as_false` | `include` / `exclude` / `treat_as_false` |
| `secondaryFilter` | Secondary Filter | `expression` | optional |  |
| `defaultValue` | Default Value | `expression` | optional |  |

Writes: `resultVar` (default `filtered`), `rejectedVar` (default `rejected`).

#### Generate ID (`generate_id`)

Generate a unique identifier

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `idType` | ID Type | `enum` | default `uuid` | `uuid` / `ulid` / `nanoid` / `hash` / `custom_pattern` / `hex` / `base58` / `urlsafe_base64` / `secure_random` |
| `resultVar` | Save result as | `output` | default `id` |  |
| `length` | Length | `integer` | default `21` | shown when `idType` = `hash` / `hex` / `base58` / `urlsafe_base64` / `secure_random`; range 1–256 |
| `size` | Size | `integer` | default `21` | shown when `idType` = `nanoid`; range 1–256 |
| `alphabet` | Alphabet | `literal` | optional | shown when `idType` = `nanoid` |
| `pattern` | Pattern | `literal` | optional | shown when `idType` = `custom_pattern` |
| `prefix` | Prefix | `literal` | optional |  |
| `separator` | Separator | `literal` | optional |  |
| `uppercase` | Uppercase | `flag` | default `false` |  |

Writes: `resultVar` (default `id`).

#### Hash Manipulate (`hash_manipulate`)

Manipulate hash/dictionary data

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `hash` |  |
| `operation` | Operation | `enum` | default `pick` | `pick` / `omit` / `keys` / `values` / `deep_merge` / `merge` / `diff` / `rename_keys` / `invert` / `deep_dup` / `symbolize_keys` / `stringify_keys` / `transform_keys` / `transform_values` / `compact` / `set_keys` / `flatten` |
| `keys` | Keys | `list` | optional | required when `operation` = `pick` / `omit`; items `literal` |
| `otherVariable` | Other hash | `input` | optional | required when `operation` = `deep_merge` / `merge` / `diff` |
| `renameMap` | Rename Map | `mapping` | optional | required when `operation` = `rename_keys`; key `literal` → value `literal` |
| `transformExpression` | Transform Expression | `expression` | optional | required when `operation` = `transform_keys` / `transform_values` |
| `computedFields` | Computed fields | `mapping` | optional | required when `operation` = `set_keys`; key `literal` → value `expression` |
| `flattenSeparator` | Flatten separator | `literal` | default `_` | shown when `operation` = `flatten` |
| `caseInsensitive` | Case Insensitive | `flag` | default `false` | shown when `operation` = `pick` / `omit` |
| `mergeStrategy` | Merge Strategy | `enum` | default `shallow` | shown when `operation` = `merge`; `shallow` / `deep` / `replace` / `append` |
| `arrayMergeMode` | Array Merge Mode | `enum` | default `concat` | shown when `operation` = `merge`; `concat` / `replace` / `unique_union` |
| `onConflict` | On Conflict | `enum` | default `last` | shown when `operation` = `merge`; `first` / `last` |

Writes: `resultVar` (default `hash`).

#### Log (`log`)

Write to logger or audit trail

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `logLevel` | Log Level | `enum` | default `info` | `debug` / `info` / `warn` / `error` / `fatal` |
| `messageTemplate` | Message Template | `literal` | required |  |
| `logger` | Logger | `enum` | default `rails` | `rails` / `stdout` / `file` |
| `filePath` | File Path | `literal` | optional | required when `logger` = `file` |
| `tags` | Tags | `mapping` | optional | key `literal` → value `input` |
| `includeBacktrace` | Include Backtrace (error only) | `flag` | default `false` |  |
| `structured` | Structured (JSON) | `flag` | default `false` |  |
| `maxMessageLength` | Max Message Length | `integer` | default `0` | range 0– |

Writes: no ctx key; the step returns success or failure.

#### Map Value (`map_value`)

Map a value through a lookup

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source Variable | `input` | required |  |
| `resultVar` | Save result as | `output` | default `mapped_value` |  |
| `matchMode` | Match Mode | `enum` | default `exact` | `exact` / `regex` / `range` |
| `mappings` | Mappings | `mapping` | optional | required when `matchMode` = `exact`; key `literal` → value `literal` |
| `rules` | Rules | `mapping` | optional | required when `matchMode` = `regex` / `range`; key `literal` → value `literal` |
| `defaultValue` | Default Value | `literal` | optional |  |
| `fallbackStrategy` | Fallback Strategy | `enum` | default `default` | `default` / `pass_through` / `raise` |
| `multiMatch` | Multi Match | `flag` | default `false` |  |
| `caseSensitive` | Case Sensitive | `flag` | default `true` |  |

Writes: `resultVar` (default `mapped_value`).

#### Math Operation (`math_operation`)

Mathematical operations

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `operation` | Operation | `enum` | default `add` | `abs` / `floor` / `ceil` / `round` / `sqrt` / `add` / `subtract` / `multiply` / `divide` / `modulo` / `power` / `min` / `max` / `random` |
| `sourceVariable` | Source | `input` | optional | required when `operation` = `abs` / `floor` / `ceil` / `round` / `sqrt` / `add` / `subtract` / `multiply` / `divide` / `modulo` / `power` / `min` / `max` |
| `otherVariable` | Other | `input` | optional | required when `operation` = `add` / `subtract` / `multiply` / `divide` / `modulo` / `power` / `min` / `max` |
| `resultVar` | Save result as | `output` | default `number` |  |
| `precision` | Precision | `integer` | optional | range 0–20 |
| `divideByZero` | Divide By Zero | `enum` | default `raise` | shown when `operation` = `divide` / `modulo`; `raise` / `nil` / `zero` / `infinity` / `nan` |
| `minValue` | Min Value | `integer` | default `0` | shown when `operation` = `random` |
| `maxValue` | Max Value | `integer` | default `100` | shown when `operation` = `random` |

Writes: `resultVar` (default `number`).

#### Parse Data (`parse_data`)

Parse data from format

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source Variable | `input` | required |  |
| `resultVar` | Save result as | `output` | default `data` |  |
| `format` | Format | `enum` | default `json` | `json` / `csv` / `xml` / `yaml` / `toml` / `properties` |
| `csvHeaders` | CSV Headers | `flag` | default `true` | shown when `format` = `csv` |
| `csvDelimiter` | CSV Delimiter | `literal` | default `,` | shown when `format` = `csv` |
| `quoteChar` | Quote Character | `literal` | default `"` | shown when `format` = `csv` |
| `skipRows` | Skip Rows | `integer` | default `0` | shown when `format` = `csv`; range 0–10000 |
| `encoding` | Encoding | `enum` | default `utf-8` | shown when `format` = `csv`; `utf-8` / `utf-16` / `ascii` / `iso-8859-1` |
| `colTypes` | Column Types | `mapping` | optional | shown when `format` = `csv`; key `literal` → value `literal` |
| `xmlRoot` | XML Root | `literal` | optional | shown when `format` = `xml` |
| `strictMode` | Strict Mode | `flag` | default `false` |  |
| `symbolizeKeys` | Symbolize Keys | `flag` | default `false` | shown when `format` = `json` / `yaml` / `toml` |

Writes: `resultVar` (default `data`).

#### Read a Constant (`read_setting`)

Read a Constant's options or the label for a value, using this customer's override when present.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `constant` | Constant | `reference` | required | source `constants` |
| `returns` | Returns | `enum` | default `options` | `options` / `label` |
| `value` | Value | `expression` | optional | required when `returns` = `label` |
| `resultVar` | Save result as | `output` | default `constant_options` |  |

Writes: `resultVar` (default `constant_options`).

#### Regex Extract (`regex_extract`)

Extract data using regex patterns

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source Variable | `input` | required |  |
| `resultVar` | Save result as | `output` | default `match` |  |
| `pattern` | Pattern | `literal` | required |  |
| `operation` | Operation | `enum` | default `match` | `match` / `scan` / `test` / `replace` |
| `flags` | Flags | `enum` | default `none` | `i` / `m` / `x` / `none` |
| `regexFlags` | Regex Flags | `literal` | optional |  |
| `returnType` | Return Type | `enum` | default `first` | shown when `operation` = `match`; `first` / `all` / `named_hash` |
| `captureGroup` | Capture Group | `integer` | default `0` | shown when `returnType` = `first`; range 0–99 |
| `replacement` | Replacement | `literal` | optional | required when `operation` = `replace` |
| `fallbackValue` | Fallback Value | `expression` | default `nil` | shown when `operation` = `match` |

Writes: `resultVar` (default `match`).

#### Serialize Data (`serialize_data`)

Serialize data to format

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source Variable | `input` | required |  |
| `resultVar` | Save result as | `output` | default `serialized` |  |
| `format` | Format | `enum` | default `json` | `json` / `xml` / `yaml` / `msgpack` |
| `pretty` | Pretty Print | `flag` | default `false` | shown when `format` = `json` |
| `jsonMaxDepth` | JSON Max Depth | `integer` | default `0` | shown when `format` = `json`; range 0–100 |
| `includeRoot` | Include Root | `flag` | default `false` | shown when `format` = `xml` |
| `rootElement` | Root Element | `literal` | default `data` | shown when `format` = `xml` |
| `excludeNils` | Exclude Nils | `flag` | default `false` |  |

Writes: `resultVar` (default `serialized`).

#### String Manipulate (`string_manipulate`)

String manipulation operations

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `text` |  |
| `operation` | Operation (single) | `enum` | default `strip` | `split` / `join` / `strip` / `pad_left` / `pad_right` / `truncate` / `upcase` / `downcase` / `capitalize` / `camelize` / `underscore` / `reverse` / `replace` / `gsub` / `unicode_normalize` / `html_escape` / `html_unescape` / `base64_encode` / `base64_decode` |
| `operations` | Operations Pipeline | `mapping` | optional | key `literal` → value `literal` |
| `regexEscape` | Regex Escape | `flag` | default `false` |  |
| `encoding` | Encoding | `enum` | default `utf8` | `utf8` / `ascii` / `latin1` |
| `delimiter` | Delimiter | `literal` | default `,` | shown when `operation` = `split` / `join` |
| `length` | Length | `integer` | default `10` | shown when `operation` = `pad_left` / `pad_right` / `truncate`; range 1–10000 |
| `padChar` | Pad Char | `literal` | default ` ` | shown when `operation` = `pad_left` / `pad_right` |
| `pattern` | Pattern | `literal` | optional | shown when `operation` = `replace` / `gsub` |
| `replacement` | Replacement | `literal` | optional | shown when `operation` = `replace` / `gsub` |
| `urlSafe` | URL Safe | `flag` | default `false` | shown when `operation` = `base64_encode` / `base64_decode` |
| `stripPadding` | Strip Padding | `flag` | default `false` | shown when `operation` = `base64_encode` |
| `inputEncoding` | Input Encoding | `enum` | default `utf8` | shown when `operation` = `base64_encode`; `utf8` / `binary` |
| `lineWidth` | Line Width | `integer` | default `0` | shown when `operation` = `base64_encode`; range 0–1000 |

Writes: `resultVar` (default `text`).

#### Type Cast (`type_cast`)

Cast value to different type

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source Key | `input` | required |  |
| `resultVar` | Save result as | `output` | default `cast_value` |  |
| `targetType` | Target Type | `enum` | default `string` | `string` / `integer` / `float` / `boolean` / `date` / `datetime` / `array` / `hash` / `big_decimal` / `rational` / `complex` / `symbol` / `time` / `date_time` / `json` |
| `format` | Format | `literal` | optional |  |
| `timezoneAware` | Timezone Aware | `flag` | default `false` |  |
| `strictBoolean` | Strict Boolean | `flag` | default `false` |  |
| `timezone` | Timezone | `literal` | optional |  |

Writes: `resultVar` (default `cast_value`).

### Communication (`communication`)

#### HTTP request (`api_call`)

Make an external HTTP request.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `httpMethod` | HTTP Method | `enum` | default `GET` | `GET` / `HEAD` / `POST` / `PUT` / `PATCH` / `DELETE` / `OPTIONS` |
| `url` | URL | `expression` | required |  |
| `headers` | Headers | `mapping` | optional | key `literal` → value `literal` |
| `queryParams` | Query params | `mapping` | optional | key `literal` → value `literal` |
| `bodyTemplate` | Body | `expression` | optional | shown when `httpMethod` = `POST` / `PUT` / `PATCH` |
| `bodyFormat` | Body format | `enum` | default `json` | shown when `httpMethod` = `POST` / `PUT` / `PATCH`; `json` / `form` / `text` / `xml` / `binary` |
| `authType` | Auth type | `enum` | default `none` | `none` / `bearer` / `basic` / `apiKey` |
| `authToken` | Auth token | `expression` | optional | required when `authType` = `bearer` / `apiKey` |
| `authUsername` | Username | `expression` | optional | required when `authType` = `basic` |
| `authPassword` | Password | `expression` | optional | required when `authType` = `basic` |
| `apiKeyHeader` | API key header | `literal` | default `X-API-Key` | shown when `authType` = `apiKey` |
| `responseFormat` | Response format | `enum` | default `json` | `json` / `text` / `binary` |
| `responseParseKey` | Parse key | `literal` | optional |  |
| `followRedirects` | Follow redirects | `flag` | default `true` |  |
| `maxRedirects` | Max redirects | `integer` | default `5` | shown when `followRedirects` = `true`; range 0–20 |
| `idempotencyKey` | Idempotency key | `expression` | optional |  |
| `resultVar` | Save result as | `output` | default `api_response` |  |

Writes: `resultVar` (default `api_response`).

Advanced HTTP options: transport retry, timeouts, circuit breaker.

#### Create notification (`create_notification`)

Create an in-app notification for a user of this customer

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `recipient` | Recipient | `expression` | default `ctx[:current_user_id]` |  |
| `title` | Title | `localized_text` | required |  |
| `body` | Body | `localized_text` | required |  |
| `page` | Page | `reference` | optional | source `pages` |

Writes: no ctx key; the step returns success or failure.

#### Send SMS (`send_sms`)

Send an SMS using an approved template.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `templateKey` | Template | `reference` | required | source `sms_templates` |
| `to` | To | `input` | default `model.phone` |  |
| `vars` | Template variables | `mapping` | optional | key `literal` → value `expression` |
| `idempotencyKey` | Idempotency key | `expression` | optional |  |
| `resultVar` | Save result as | `output` | default `sms_message_id` |  |

Writes: `resultVar` (default `sms_message_id`).

#### Send Template Email (`send_template_email`)

Send a pre-defined email template via the Emails gateway

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `templateId` | Template | `reference` | required | source `email_templates` |
| `to` | To | `input` | required |  |
| `vars` | Template variables | `mapping` | optional | key `literal` → value `literal` |
| `cc` | CC | `expression` | optional |  |
| `bcc` | BCC | `expression` | optional |  |
| `replyTo` | Reply-To | `expression` | optional |  |
| `idempotencyKey` | Idempotency key | `expression` | optional |  |
| `resultVar` | Save result as | `output` | default `email_message_id` |  |

Writes: `resultVar` (default `email_message_id`).

#### Send Webhook (`send_webhook`)

Outbound webhook POST

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `url` | URL | `expression` | required |  |
| `payloadExpression` | Payload | `expression` | required |  |
| `headers` | Headers | `mapping` | optional | key `literal` → value `literal` |
| `secretExpression` | Signing secret | `expression` | optional |  |
| `hmacAlgorithm` | HMAC algorithm | `enum` | default `sha256` | `sha256` / `sha512` / `sha1` |
| `signatureHeader` | Signature header | `literal` | default `X-Signature` |  |
| `idempotencyKey` | Idempotency key | `expression` | optional |  |
| `contentType` | Content type | `enum` | default `application/json` | `application/json` / `application/x-www-form-urlencoded` |
| `resultVar` | Save result as | `output` | default `webhook_response` |  |

Writes: `resultVar` (default `webhook_response`).

Advanced HTTP options: transport retry, timeouts, circuit breaker.

### Security (`security`)

#### Authenticate (`authenticate`)

Authenticate user or request

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `authMethod` | Auth Method | `enum` | default `password` | `password` / `token` / `api_key` / `session` |
| `credentialSource` | Credential Source | `enum` | default `ctx` | `ctx` / `params` |
| `sourceVariable` | Source | `input` | optional | required when `authMethod` = `password` / `token` / `api_key` |
| `resultVar` | Save result as | `output` | default `authenticated_user` |  |
| `userVariable` | User Variable | `input` | default `user` | shown when `authMethod` = `password` |
| `tokenType` | Token Type | `enum` | default `bearer` | shown when `authMethod` = `token`; `bearer` / `basic` / `custom` |
| `expectedKeyVariable` | Expected Key | `input` | optional | required when `authMethod` = `token` / `api_key` |

Writes: `resultVar` (default `authenticated_user`).

#### Authorize (`authorize`)

Role or CanCanCan ability check

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `authType` | Auth Type | `enum` | default `role_check` | `role_check` / `ability_check` / `multi_role` |
| `userExpression` | User | `input` | default `current_user` |  |
| `roleName` | Role Name | `enum` | default `admin` | shown when `authType` = `role_check`; `owner` / `admin` / `member` |
| `abilityAction` | Ability Action | `literal` | optional | required when `authType` = `ability_check` |
| `abilityResource` | Ability Resource | `input` | optional | required when `authType` = `ability_check` |
| `roleList` | Role List | `list` | optional | required when `authType` = `multi_role`; items `literal` |
| `roleMode` | Role Mode | `enum` | default `any_of` | shown when `authType` = `multi_role`; `any_of` / `all_of` |

Writes: no ctx key; the step returns success or failure.

#### Register member (`register_member`)

Register a public visitor as a passwordless member

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `personVar` | Person | `input` | default `model` |  |
| `resultVar` | Save result as | `output` | default `registration` |  |

Security category, version `1.0.0`, `single_use: true`, `privileged: false`. Emits `FlowchartRuntime::Registration.call(ctx, person: <personVar>)`. Rule order and the identical browser response for `created` / `existing` are on [Flowchart runtime](flowchart-runtime). Writes `resultVar` (`{ "status" => "created" | "existing" }`) and, when no preset is already set, `ctx[:submission_outcome]` with preset `registration_pending` ("Check your email to finish signing up." / 「请查收邮件以完成注册。」). That preset is **not** in the `set_submission_outcome` enum.

Failures: `register_member.public_only` ("Registration is only available to visitors who aren't signed in."), `register_member.person_entity_required` ("Registration needs a form on a person entity."), `register_member.signup_disabled` ("Sign-up is turned off."), `register_member.unavailable` ("We couldn't complete sign-up right now. Please try again later.") from `config/locales/flowchart_actions_security.*.yml`. A full member quota is not a failure: it answers like an address that already has an account, so the response never reveals which emails exist. Invalid identity is `record_invalid`, the same path `save_model` uses.

Writes: `resultVar` (default `registration`), `ctx[:submission_outcome]` when it was unset.

#### Decrypt Data (`decrypt_data`)

Decrypt encrypted data

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `decrypted` |  |
| `algorithm` | Algorithm | `enum` | default `aes-256-gcm` | `aes-256-gcm` |
| `keySource` | Key Source | `enum` | default `credentials` | `credentials` / `env` / `ctx` / `derived` |
| `keyPath` | Key Path | `literal` | optional | required when `keySource` = `env` / `ctx`; shown when `keySource` = `credentials` / `env` / `ctx` |
| `deriveKeyFrom` | Derive Key From | `input` | optional | required when `keySource` = `derived` |
| `deriveKeySalt` | Derive Key Salt | `literal` | optional | shown when `keySource` = `derived` |
| `encoding` | Encoding | `enum` | default `base64` | `hex` / `base64` / `base64url` / `raw` / `binary` |

Writes: `resultVar` (default `decrypted`).

#### Encrypt Data (`encrypt_data`)

Encrypt sensitive data

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `encrypted` |  |
| `algorithm` | Algorithm | `enum` | default `aes-256-gcm` | `aes-256-gcm` |
| `keySource` | Key Source | `enum` | default `credentials` | `credentials` / `env` / `ctx` / `derived` |
| `keyPath` | Key Path | `literal` | optional | required when `keySource` = `env` / `ctx`; shown when `keySource` = `credentials` / `env` / `ctx` |
| `deriveKeyFrom` | Derive Key From | `input` | optional | required when `keySource` = `derived` |
| `deriveKeySalt` | Derive Key Salt | `literal` | optional | shown when `keySource` = `derived` |
| `encoding` | Encoding | `enum` | default `base64` | `hex` / `base64` / `base64url` / `raw` |

Writes: `resultVar` (default `encrypted`).

#### Generate Token (`generate_token`)

Generate authentication token

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `tokenType` | Token Type | `enum` | default `jwt` | `jwt` / `hmac` / `numeric_otp` |
| `resultVar` | Save result as | `output` | default `token` |  |
| `tokenLength` | Token Length | `integer` | default `6` | shown when `tokenType` = `numeric_otp`; range 4–12 |
| `dataVariable` | Data Variable | `input` | optional | required when `tokenType` = `hmac` |
| `digest` | Digest | `enum` | default `sha256` | shown when `tokenType` = `hmac`; `sha1` / `sha256` / `sha512` |
| `payloadVariable` | Payload Variable | `input` | optional | shown when `tokenType` = `jwt` |
| `issuer` | Issuer | `literal` | optional | shown when `tokenType` = `jwt` |
| `audience` | Audience | `literal` | optional | shown when `tokenType` = `jwt` |
| `notBefore` | Not Before | `expression` | optional | shown when `tokenType` = `jwt` |
| `expiresIn` | Expires In | `literal` | optional | shown when `tokenType` = `jwt` |
| `claims` | Claims | `mapping` | optional | shown when `tokenType` = `jwt`; key `literal` → value `expression` |
| `keyId` | Key Id | `literal` | optional | shown when `tokenType` = `jwt` |
| `algorithm` | Algorithm | `enum` | default `HS256` | shown when `tokenType` = `jwt`; `HS256` / `HS384` / `HS512` / `RS256` |
| `secretSource` | Secret Source | `enum` | default `credentials` | shown when `tokenType` = `jwt`; `credentials` / `env` / `ctx` |
| `secretVariable` | Secret Variable | `literal` | optional | required when `tokenType` = `jwt` / `hmac` |

Writes: `resultVar` (default `token`).

#### Hash Data (`hash_data`)

Generate hash digest

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `hashed` |  |
| `algorithm` | Algorithm | `enum` | default `sha256` | `bcrypt` / `scrypt` / `argon2` / `pbkdf2` / `sha256` / `sha512` / `md5` |
| `cost` | Cost (bcrypt) | `integer` | default `12` | shown when `algorithm` = `bcrypt`; range 4–31 |
| `iterations` | Iterations | `integer` | default `100000` | shown when `algorithm` = `pbkdf2` / `scrypt`; range 1000–1000000 |
| `salt` | Salt | `input` | optional |  |
| `pepper` | Pepper | `input` | optional |  |
| `encoding` | Encoding | `enum` | default `hex` | shown when `algorithm` = `sha256` / `sha512` / `md5` / `pbkdf2`; `hex` / `base64` / `base64url` |

Writes: `resultVar` (default `hashed`).

#### Mask Data (`mask_data`)

Mask sensitive data fields

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `masked` |  |
| `maskType` | Mask Type | `enum` | default `custom` | `last4` / `first1_last1` / `email` / `phone` / `ssn` / `credit_card` / `full` / `custom` |
| `visibleStart` | Visible Start | `integer` | default `0` | shown when `maskType` = `last4` / `first1_last1` / `phone` / `ssn` / `credit_card` / `custom`; range 0– |
| `visibleEnd` | Visible End | `integer` | default `0` | shown when `maskType` = `last4` / `first1_last1` / `phone` / `ssn` / `credit_card` / `custom`; range 0– |
| `maskChar` | Mask Character | `literal` | default `*` |  |
| `preserveFormat` | Preserve Format | `flag` | default `true` | shown when `maskType` = `phone` / `ssn` / `credit_card` / `last4` / `first1_last1` |
| `regexPattern` | Regex Pattern | `literal` | optional | shown when `maskType` = `custom` |

Writes: `resultVar` (default `masked`).

#### Sanitize Input (`sanitize_input`)

Sanitize user input

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `sanitized` |  |
| `sanitizer` | Sanitizer | `enum` | default `strip_tags` | `strip_tags` / `escape_html` / `rails` / `loofah` / `scrubber` |
| `scrubberVariable` | Scrubber Variable | `input` | optional | required when `sanitizer` = `scrubber` |
| `allowedTags` | Allowed Tags | `list` | optional | shown when `sanitizer` = `rails`; items `literal` |
| `allowedAttributes` | Allowed Attributes | `list` | optional | shown when `sanitizer` = `rails`; items `literal` |
| `stripTags` | Strip Tags | `flag` | default `false` |  |
| `removeNullBytes` | Remove Null Bytes | `flag` | default `true` |  |
| `maxLength` | Max Length | `integer` | default `0` | range 0– |

Writes: `resultVar` (default `sanitized`).

#### Verify Token (`verify_token`)

Verify token validity

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `secretKey` | Secret Key | `input` | required |  |
| `algorithm` | Algorithm (fallback) | `enum` | default `HS256` | `HS256` / `HS384` / `HS512` / `RS256` |
| `algorithmAllowlist` | Algorithm Allowlist | `list` | optional | items `literal` |
| `verifyIssuer` | Verify Issuer (iss) | `literal` | optional |  |
| `verifyAudience` | Verify Audience (aud) | `literal` | optional |  |
| `leewaySeconds` | Leeway Seconds | `integer` | default `0` | range 0– |
| `requiredClaims` | Required Claims | `mapping` | optional | key `literal` → value `literal` |
| `resultVar` | Save result as | `output` | default `claims` |  |

Writes: `resultVar` (default `claims`).

### Background (`background`)

#### Run background job (`enqueue_job`)

Queue a background job now, at a time, after a delay, or on a recurring schedule.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `jobClass` | Job Class | `reference` | required | source `job_classes` |
| `when` | When | `enum` | default `now` | `now` / `at` / `after` / `recurring` |
| `jobArgs` | Job Arguments | `expression` | optional |  |
| `queueName` | Queue Name | `enum` | default `default` | `default` / `low` / `high` / `mailers` |
| `priority` | Priority | `integer` | optional | range 0–1000 |
| `runAt` | Run At | `expression` | optional | required when `when` = `at` |
| `waitSeconds` | Wait Seconds | `integer` | optional | required when `when` = `after`; range 0–2592000 |
| `cronExpression` | Cron Expression | `literal` | optional | shown when `when` = `recurring` |
| `timezone` | Timezone | `literal` | default `UTC` | shown when `when` = `recurring` |
| `intervalSeconds` | Interval Seconds | `integer` | default `3600` | shown when `when` = `recurring`; range 1–86400 |
| `recurrenceLimit` | Recurrence Limit | `integer` | default `1` | shown when `when` = `recurring`; range 1–100 |
| `resultVar` | Save result as | `output` | default `enqueued_job_id` |  |

Writes: `resultVar` (default `enqueued_job_id`).

### File (`file`)

#### Compress Files (`compress_files`)

Compress files into archive

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `entries` | Entries | `mapping` | required | key `literal` → value `literal` |
| `literalEntries` | Literal Entries | `mapping` | optional | key `literal` → value `literal` |
| `format` | Format | `enum` | default `zip` | `zip` / `tar` / `gz` / `tar_gz` |
| `compressionLevel` | Compression Level | `integer` | optional | range 0–9 |
| `includeHidden` | Include Hidden | `flag` | default `false` |  |
| `resultVar` | Save result as | `output` | default `archive` |  |

Writes: `resultVar` (default `archive`).

#### Decompress Files (`decompress_files`)

Extract files from archive

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `extracted` |  |
| `format` | Format | `enum` | default `auto` | `auto` / `zip` / `tar` / `gz` / `tar_gz` |
| `filter` | Filter (fnmatch) | `literal` | optional |  |

Writes: `resultVar` (default `extracted`).

#### Download File (`download_file`)

Download file from remote source

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `url` | URL | `literal` | optional |  |
| `urlVariable` | URL Variable | `input` | optional |  |
| `resultVar` | Save result as | `output` | default `file_content` |  |
| `destination` | Destination | `enum` | default `ctx_var` | `ctx_var` / `temp_file` / `active_storage` |
| `maxSizeBytes` | Max Size (bytes) | `integer` | optional | range 1–104857600 |
| `followRedirects` | Follow Redirects | `flag` | default `true` |  |
| `maxRedirects` | Max Redirects | `integer` | default `3` | shown when `followRedirects` = `true`; range 0–10 |
| `headers` | Headers | `mapping` | optional | key `literal` → value `literal` |
| `validateChecksum` | Validate Checksum | `literal` | optional |  |

Writes: `resultVar` (default `file_content`).

Advanced HTTP options: transport retry, timeouts, circuit breaker.

#### Generate document (`generate_document`)

Generate a PDF document from a title, body, and optional table.

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `title` | Title | `template` | required |  |
| `body` | Body | `template` | required |  |
| `sourceVariable` | Table source | `input` | optional |  |
| `columns` | Table columns | `mapping` | optional | key `literal` → value `literal` |
| `filename` | Filename | `template` | default `document.pdf` |  |
| `resultVar` | Save result as | `output` | default `document` |  |

Writes: `resultVar` (default `document`).

#### Generate File (`generate_file`)

Generate PDF/CSV/Excel/JSON/XML/TXT

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `resultVar` | Save result as | `output` | default `generated_file` |  |
| `fileType` | File Type | `enum` | default `csv` | `csv` / `xlsx` / `pdf` / `json` / `xml` / `txt` |
| `outputDestination` | Output Destination | `enum` | default `ctx_var` | `ctx_var` / `active_storage` |
| `columns` | Columns | `mapping` | optional | shown when `fileType` = `csv` / `xlsx`; key `literal` → value `literal` |
| `sheetName` | Sheet Name | `literal` | default `Sheet1` | shown when `fileType` = `xlsx` |
| `autoFilter` | Auto Filter | `flag` | default `false` | shown when `fileType` = `xlsx` |
| `pageSize` | Page Size | `enum` | default `letter` | shown when `fileType` = `pdf`; `letter` / `a4` / `legal` |
| `pretty` | Pretty | `flag` | default `false` | shown when `fileType` = `json` |
| `rootElement` | Root Element | `literal` | default `root` | shown when `fileType` = `xml` |
| `lineEnding` | Line Ending | `enum` | default `lf` | shown when `fileType` = `txt`; `lf` / `crlf` |
| `filenameTemplate` | Filename | `literal` | optional |  |
| `encoding` | Encoding | `enum` | default `utf-8` | shown when `fileType` = `csv`; `utf-8` / `utf-16` / `ascii` / `iso-8859-1` |
| `delimiter` | Delimiter | `literal` | default `,` | shown when `fileType` = `csv` |
| `headerRow` | Header Row | `flag` | default `true` | shown when `fileType` = `csv` |
| `quoteStrings` | Force Quote Strings | `flag` | default `false` | shown when `fileType` = `csv` |
| `includeBom` | Include UTF-8 BOM | `flag` | default `false` | shown when `fileType` = `csv` |
| `nestedSeparator` | Nested Separator | `literal` | default `.` | shown when `fileType` = `csv` |

Writes: `resultVar` (default `generated_file`).

#### Upload File (`upload_file`)

Upload a file to Active Storage

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `service` | Service | `enum` | default `active_storage` | `active_storage` |
| `attachmentName` | Attachment Name | `literal` | required |  |
| `sourceVariable` | Source | `input` | required |  |
| `modelVariable` | Record | `input` | default `model` |  |
| `filenameVariable` | Filename Variable | `input` | optional |  |
| `contentTypeVariable` | Content Type Variable | `input` | optional |  |
| `maxSizeBytes` | Max Size (bytes) | `integer` | optional | range 1–104857600 |
| `allowedTypes` | Allowed MIME Types | `list` | optional | items `literal` |

Writes: no ctx key; the step returns success or failure.

### Caching (`caching`)

#### Cache Delete (`cache_delete`)

Delete value from cache

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `scope` | Scope | `enum` | default `key` | `key` / `pattern` / `namespace` / `all` / `tagged` |
| `cacheKey` | Cache Key / Pattern / Namespace | `literal` | optional | required when `scope` = `key` |
| `tags` | Tags | `list` | optional | required when `scope` = `tagged`; items `literal` |
| `confirmPattern` | Pattern Size Guard | `flag` | default `true` | shown when `scope` = `pattern` |

Writes: no ctx key; the step returns success or failure.

#### Cache Fetch (`cache_fetch`)

Fetch from cache with fallback block

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `cacheKey` | Cache Key | `literal` | required |  |
| `fallbackExpression` | Fallback Expression | `input` | required |  |
| `resultVar` | Result Var | `output` | default `cached` |  |
| `ttl` | Ttl | `integer` | optional | range 1–86400 |
| `raceConditionTtl` | Race Condition TTL (s) | `integer` | optional | range 1–3600 |
| `forceRefresh` | Force Refresh | `flag` | default `false` |  |
| `skipNilCache` | Skip Nil Cache | `flag` | default `true` |  |
| `versionKey` | Version Key | `literal` | optional |  |

Writes: `resultVar` (default `cached`).

#### Cache Read (`cache_read`)

Read value from cache

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `cacheKey` | Cache Key | `literal` | required |  |
| `resultVar` | Result Variable | `output` | default `cached` |  |
| `namespace` | Namespace | `literal` | optional |  |
| `decompressOnRead` | Decompress On Read | `flag` | default `false` |  |
| `versionCheck` | Version Check | `literal` | optional |  |
| `onMiss` | On Miss | `enum` | default `nil` | `nil` / `default` |
| `defaultValue` | Default Value | `literal` | optional | required when `onMiss` = `default` |

Writes: `resultVar` (default `cached`).

#### Cache Write (`cache_write`)

Write value to cache

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `cacheKey` | Cache Key | `literal` | required |  |
| `action` | Action | `enum` | default `write` | `write` / `write_if_absent` |
| `sourceVariable` | Source Variable | `input` | default `data` |  |
| `ttl` | TTL (seconds) | `integer` | optional | range 1–86400 |
| `compress` | Compress | `flag` | default `true` |  |
| `raw` | Raw | `flag` | default `false` |  |
| `race_condition_ttl` | Race Condition TTL (seconds) | `integer` | optional | range 1–3600 |
| `namespace` | Namespace | `literal` | optional |  |
| `version` | Version | `literal` | optional |  |
| `tags` | Tags | `list` | optional | items `literal` |

Writes: no ctx key; the step returns success or failure.

### Concurrency (`concurrency`)

#### Acquire Lock (`acquire_lock`)

Acquire a distributed lock

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `lockKey` | Lock Key | `literal` | optional |  |
| `lockKeyVariable` | Lock Key Variable | `input` | optional |  |
| `holderIdentity` | Holder Identity | `literal` | optional |  |
| `ttl` | TTL (seconds) | `integer` | default `30` | range 1–3600 |
| `onConflict` | On Conflict | `enum` | default `fail` | `fail` / `raise` / `skip` |
| `lockKeyVar` | Save lock key as | `output` | default `_cache_lock_key` |  |
| `tokenVar` | Save lock token as | `output` | default `_lock_token` |  |

Writes: `lockKeyVar` (default `_cache_lock_key`), `tokenVar` (default `_lock_token`).

#### Release Lock (`release_lock`)

Release a distributed lock

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `lockKey` | Lock Key | `literal` | optional |  |
| `lockKeyVariable` | Lock Key Variable | `input` | optional |  |
| `holderIdentity` | Holder Identity | `literal` | optional |  |
| `onMissing` | On Missing | `enum` | default `ignore` | `ignore` / `fail` / `log` |

Writes: no ctx key; the step returns success or failure.

### Resilience (`resilience`)

#### Idempotency Check (`idempotency_check`)

Ensure idempotent execution

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `keyStrategy` | Key strategy | `enum` | default `ctx_field` | `ctx_field` / `hash_of_inputs` / `explicit` |
| `ctxField` | Context field | `input` | optional | required when `keyStrategy` = `ctx_field` |
| `explicitKey` | Explicit key | `literal` | optional | required when `keyStrategy` = `explicit` |
| `ttlSeconds` | TTL (seconds) | `integer` | default `3600` | range 1–2592000 |
| `resultVar` | Save result as | `output` | default `idempotency_result` |  |

Writes: `resultVar` (default `idempotency_result`).

#### Rate Limiter (`rate_limiter`)

Apply rate limiting

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `limiterName` | Limiter name | `literal` | required |  |
| `capacity` | Capacity | `integer` | default `100` | range 1–100000 |
| `window` | Window | `integer` | default `60` | range 1–86400 |
| `onExceed` | On exceed | `enum` | default `fail` | `fail` / `skip` |
| `resultVar` | Save result as | `output` | default `throttle_state` |  |

Writes: `resultVar` (default `throttle_state`).

### Scheduling (`scheduling`)

#### Business Hours Check (`business_hours_check`)

Check if within business hours

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `schedule` | Weekly Schedule | `mapping` | required | key `literal` → value `literal` |
| `holidays` | Holidays | `mapping` | optional | key `literal` → value `literal` |
| `timezone` | Timezone | `literal` | default `UTC` |  |
| `timeVariable` | Time Variable | `input` | optional |  |
| `resultMode` | Result Mode | `enum` | default `bool` | `bool` / `next_open` / `minutes_until_open` |
| `resultVar` | Result Variable | `output` | default `hours_status` |  |

Writes: `resultVar` (default `hours_status`).

#### Deadline Check (`deadline_check`)

Check if deadline has passed

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `deadlineVariable` | Deadline Variable | `input` | default `deadline` |  |
| `deadlineFormat` | Deadline Format | `enum` | default `auto` | `iso8601` / `rfc2822` / `auto` |
| `referenceTime` | Reference Time | `input` | optional |  |
| `gracePeriodSeconds` | Grace Period (seconds) | `integer` | default `0` | range 0–31536000 |
| `behaviorOnBreach` | Behavior On Breach | `enum` | default `mark` | `mark` / `raise` |
| `resultVar` | Result Var | `output` | default `deadline_status` |  |
| `breachedVar` | Breached Variable | `output` | default `deadline_breached` |  |

Writes: `resultVar` (default `deadline_status`), `breachedVar` (default `deadline_breached`).

### Payments (`payments`)

#### Refund payment (`refund_payment`)

Refund a captured payment of this customer

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `payment` | Payment | `expression` | required |  |
| `amount` | Amount | `expression` | required |  |
| `reason` | Reason | `expression` | optional |  |

Writes: no ctx key; the step returns success or failure.

#### Request payment (`request_payment`)

Hand off to checkout after the submission, which creates the payment order

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `amount` | Amount | `expression` | required |  |
| `currency` | Currency | `expression` | required |  |
| `subject` | Subject | `expression` | required |  |

Writes: `ctx[:submission_outcome]["handoff"]`.

### Submission outcome (`outcome`)

#### Set submission outcome (`set_submission_outcome`)

Set the public flash and post-submit destination

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `preset` | Preset | `enum` | default `submitted` | `submitted` / `saved` / `thank_you` / `custom`. `registration_pending` is set by `register_member`, not offered here. |
| `message` | Message | `localized_text` | optional | required when `preset` = `custom` |
| `flash` | Flash | `enum` | default `notice` | `notice` / `alert` |
| `target` | Target | `enum` | default `form` | `form` / `page` |
| `page` | Page | `reference` | optional | required when `target` = `page`; source `pages` |

Writes: `ctx[:submission_outcome]`.

### Service (`service`)

#### Invoke Service (`invoke_service`)

Invoke an external or internal service

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `serviceClass` | Service Class | `reference` | required | source `service_classes` |
| `invocationStyle` | Invocation Style | `enum` | default `call` | `call` / `new_and_call` / `class_method` / `instance_method` |
| `methodName` | Method Name | `literal` | optional | required when `invocationStyle` = `class_method` / `instance_method` |
| `args` | Positional Args | `mapping` | optional | key `literal` → value `literal` |
| `kwargs` | Keyword Args | `mapping` | optional | key `literal` → value `literal` |
| `resultVar` | Save result as | `output` | default `service_result` |  |

Writes: `resultVar` (default `service_result`).

### Utility (`utility`)

#### AI Inference (`ai_inference`)

Run AI/ML inference

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `provider` | Provider | `enum` | default `openai` | `openai` / `anthropic` / `cohere` / `ollama` |
| `model` | Model | `literal` | default `gpt-4o` |  |
| `promptTemplate` | Prompt Template | `literal` | required |  |
| `systemPrompt` | System Prompt | `literal` | optional |  |
| `maxTokens` | Max Tokens | `integer` | default `1024` | range 1–128000 |
| `temperature` | Temperature | `decimal` | default `0.7` | range 0–2 |
| `tools` | Tools | `list` | optional | items `literal` |
| `outputFormat` | Output Format | `enum` | default `text` | `text` / `json` / `structured` |
| `resultVar` | Save result as | `output` | default `ai_response` |  |

Writes: `resultVar` (default `ai_response`).

Advanced HTTP options: timeouts, circuit breaker.

#### Audit Log (`audit_log`)

Write to audit log

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `eventType` | Event Type | `literal` | required |  |
| `resourceType` | Resource Type | `literal` | optional |  |
| `resourceId` | Resource ID (ctx key) | `input` | optional |  |
| `actorId` | Actor ID (ctx key) | `input` | default `current_user_id` |  |
| `actorType` | Actor Type | `literal` | optional |  |
| `metadata` | Metadata | `mapping` | optional | key `literal` → value `input` |
| `ipAddress` | IP Address (ctx key) | `input` | default `request_ip` |  |
| `userAgent` | User Agent (ctx key) | `input` | default `user_agent` |  |
| `severity` | Severity | `enum` | default `info` | `debug` / `info` / `warn` / `error` / `critical` |

Writes: no ctx key; the step returns success or failure.

#### Barcode Generate (`barcode_generate`)

Generate barcode

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `sourceVariable` | Source | `input` | required |  |
| `format` | Barcode Format | `enum` | default `code128` | `code128` / `code39` / `ean13` / `ean8` / `upca` / `itf` / `codabar` / `qr` |
| `width` | Width (xdim) | `integer` | default `2` | shown when `format` = `code128` / `code39` / `ean13` / `ean8` / `upca` / `itf` / `codabar`; range 1–32 |
| `height` | Height | `integer` | default `100` | shown when `format` = `code128` / `code39` / `ean13` / `ean8` / `upca` / `itf` / `codabar`; range 1–1000 |
| `margin` | Margin | `integer` | default `10` | range 0–100 |
| `outputFormat` | Output Format | `enum` | default `png` | `png` / `svg` / `jpg` / `base64` / `ascii` |
| `includeText` | Include Text | `flag` | default `true` | shown when `outputFormat` = `svg` |
| `textFont` | Text Font | `enum` | default `Helvetica` | shown when `outputFormat` = `svg`; `Helvetica` / `Arial` / `DejaVuSans` / `FreeSans` |
| `size` | Size | `integer` | default `4` | shown when `format` = `qr`; range 1–40 |
| `errorCorrection` | Error Correction | `enum` | default `M` | shown when `format` = `qr`; `L` / `M` / `Q` / `H` |
| `colorDark` | Dark Color | `literal` | default `#000000` | shown when `format` = `qr` |
| `colorLight` | Light Color | `literal` | default `#FFFFFF` | shown when `format` = `qr` |
| `resultVar` | Save result as | `output` | default `barcode_image` |  |

Writes: `resultVar` (default `barcode_image`).

#### Currency Convert (`currency_convert`)

Convert between currencies

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `amount` | Amount | `input` | required |  |
| `fromCurrency` | From Currency | `literal` | default `USD` |  |
| `toCurrency` | To Currency | `literal` | required |  |
| `rateSource` | Rate Source | `enum` | default `fixed` | `ctx` / `ctx_key` / `config` / `fixed` / `external` |
| `fixedRate` | Fixed Rate | `decimal` | optional | required when `rateSource` = `fixed`; range 0– |
| `rounding` | Rounding | `enum` | default `half_up` | `half_up` / `half_even` / `floor` / `ceiling` |
| `precision` | Precision | `integer` | default `2` | range 0–12 |
| `cacheRates` | Cache Rates | `flag` | default `true` | shown when `rateSource` = `external` |
| `ratesVariable` | Rates Variable | `input` | default `exchange_rates` | shown when `rateSource` = `ctx` / `ctx_key` |
| `staticRates` | Static Rates | `mapping` | optional | shown when `rateSource` = `config`; key `literal` → value `literal` |
| `rateApiUrl` | Rate Api Url | `literal` | default `https://api.exchangerate.host/latest` | shown when `rateSource` = `external` |
| `resultVar` | Save result as | `output` | default `converted` |  |

Writes: `resultVar` (default `converted`).

Advanced HTTP options: timeouts, circuit breaker.

#### Geolocation Lookup (`geolocation_lookup`)

Look up geolocation data

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `mode` | Mode | `enum` | default `ip_to_location` | `ip_to_location` / `distance` |
| `sourceVariable` | Source | `input` | required |  |
| `otherVariable` | Other | `input` | optional | required when `mode` = `distance` |
| `provider` | Provider | `enum` | default `google` | shown when `mode` = `ip_to_location`; `google` / `mapbox` |
| `lookupKey` | Lookup Key | `enum` | default `ip` | shown when `mode` = `ip_to_location`; `ip` / `postal` / `address` / `coords` |
| `fieldsToReturn` | Fields To Return | `list` | optional | shown when `mode` = `ip_to_location`; items `literal` |
| `fallbackProvider` | Fallback Provider | `enum` | optional | shown when `mode` = `ip_to_location`; `google` / `mapbox` |
| `cacheResults` | Cache Results | `flag` | default `true` | shown when `mode` = `ip_to_location` |
| `resultVar` | Save result as | `output` | default `location` |  |

Writes: `resultVar` (default `location`).

Advanced HTTP options: timeouts, circuit breaker.

#### I18n Translate (`i18n_translate`)

Translate text using I18n

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `key` | Translation Key | `literal` | required |  |
| `locale` | Locale | `literal` | optional |  |
| `fallbackLocale` | Fallback Locale | `literal` | optional |  |
| `interpolations` | Interpolations | `mapping` | optional | key `literal` → value `literal` |
| `scope` | Scope | `literal` | optional |  |
| `default` | Default | `literal` | optional |  |
| `count` | Count | `input` | optional |  |
| `raiseOnMissing` | Raise On Missing | `flag` | default `false` |  |
| `resultVar` | Save result as | `output` | default `translated` |  |

Writes: `resultVar` (default `translated`).

#### Template Render (`template_render`)

Render template with data

| Field | Label | Role | Required / default | Notes |
|---|---|---|---|---|
| `template` | Template | `literal` | required |  |
| `variables` | Variables | `mapping` | optional | key `literal` → value `literal` |
| `strictVariables` | Strict Variables | `flag` | default `false` |  |
| `resultVar` | Save result as | `output` | default `rendered` |  |

Writes: `resultVar` (default `rendered`).

## Where to pay attention

:::attention
Do **not** branch the flowchart on `registration.status` (`created` vs `existing`) to show different results. That would reveal which emails already have accounts. The step always leaves the same `registration_pending` flash for both statuses. Identity is `ctx[:identity]` (string keys, only the identity fields placed on a person-entity page, public and admin only; members get `{}`). Continuation is `ctx[:continuation]` (symbol keys `{ action_key:, prefill: }` or nil). Neither is in `ctx[:params]`. Generic record steps never write identity keys. See [Flowchart runtime](flowchart-runtime).
:::

:::attention
`request_payment` does not create a `Payments::Order` inside the submission. `FlowchartRuntime::Payments.request` validates and normalizes the amount, currency and subject, checks that the Payment module is enabled with handoff for the run's customer, and parks `ctx[:submission_outcome]["handoff"]` (`module_key: "payment"`, `input: { amount, currency, subject }`). After a successful run, `PublicPagesController` starts the Payment module handoff and checkout (`Payments::CheckoutsController#start` → `build_order_from`) creates the single order. No charge happens inside the submission transaction.
:::

:::attention
`set_record_fields` rejects an assignment key that is not an attribute of the bound entity (`unknown_attribute`, naming the attribute and entity) only when the generator has the bound entity in its context, which is the case during activity generation. The editor's Validate button calls `validate_config` without that context, so an unknown slug surfaces when the activity is generated, not in the step form.
:::

:::attention
`generate_document` renders the PDF and stores an ActiveStorage blob; the step writes `{ blob_id, signed_id, filename, content_type, byte_size, checksum, customer_id }` to its output. It does not attach the blob to a record yet; attaching to a `file_upload` attribute is a follow-up. CJK text uses `DroidSansFallbackFull.ttf` from `vendor/fonts/` or `app/assets/fonts/` when present, else the system path `/usr/share/fonts/google-droid-sans-fonts/DroidSansFallbackFull.ttf`; when none exists, the PDF uses Helvetica and replaces CJK characters with `?`. Bundling a font (Noto Sans SC) awaits an owner decision.
:::

:::attention
`audit_log` writes a `flowchart_audit_events` row and `create_notification` writes a `flowchart_notifications` row, both in the run's transaction. There is no admin or member screen that reads either table yet; read surfaces are a follow-up.
:::

:::attention
A `reference` field is only checked for presence by `validate_config`. Each `CodeGenerators::ReferenceSources::<Source>` defines `valid?(value, customer:)`, but generation does not call it. Tenant scoping of the referenced record is enforced at runtime by the helper the step calls (`FlowchartRuntime::Constants` raises for another tenant's constant, `Notifications` drops an inaccessible page, the outcome redirect ignores a foreign page).
:::

## Key code

```ruby
# app/services/code_generators/action_catalog.rb
    CATEGORY_ORDER = %w[
      model validation data communication security background file
      caching concurrency resilience scheduling payments outcome
      service utility
    ].freeze
```

```ruby
# app/services/code_generators/action_catalog/field_presenter.rb
      ROLE_CONTROLS = {
        input: { "control" => "text", "variablePicker" => true },
        output: { "control" => "text", "variablePicker" => false },
        expression: { "control" => "code" },
        literal: { "control" => "text" },
        template: { "control" => "textarea", "multiline" => true },
        enum: { "control" => "select" },
        flag: { "control" => "toggle" },
```

```ruby
# app/services/code_generators/element_types/process/model_operations/find_model_generator.rb
          config_schema ported: true do
            enum :findBy, %w[id attribute current_person], default: "id"
            input :idSource, default: "params.id", visible: { findBy: "id" }
            entity_attribute :findField, of: :bound, example: "email", visible: { findBy: "attribute" }
            input :findValue, example: "params.email", visible: { findBy: "attribute" }
            output :resultVar, default: "model"
            requires :findField, when: { findBy: "attribute" }
            requires :findValue, when: { findBy: "attribute" }
          end
```

```ruby
# app/services/flowchart_runtime/payments.rb
    def write_handoff(ctx, amount:, currency:, subject:)
      outcome = (ctx[:submission_outcome] || {}).to_h.stringify_keys
      outcome["handoff"] = {
        "module_key" => MODULE_KEY,
        "input" => { "amount" => amount, "currency" => currency, "subject" => subject }
      }
      ctx[:submission_outcome] = outcome
    end
```

Related: [Code generators](code-generators), [Flowchart builder](flowchart-builder), [Flowchart runtime](flowchart-runtime), [Payments](payments), [SMS](sms), [Email](email), [Constants](constants).
