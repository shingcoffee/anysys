# Email Module UI/UX Phase 2 Simplification

## Purpose
Further simplify the Email module to make it easier for customers. The previous refactor introduced tabs, but we still have 7 top-level sidebar items. We want to consolidate these into fewer, more intuitive categories.

## Approach
Consolidate the sidebar into just 4 main sections:
1. **Overview**: Consolidates Dashboard and Analytics.
   - Tabs: Dashboard | Reports | Deliverability | Engagement
2. **Campaigns**: Consolidates Campaigns, Automations, Content (Templates, Assets).
   - Tabs: Campaigns | Automations | Templates | Assets
3. **Audience**: Remains the same, holding Contacts, Lists, Segments, Tags, Signup Forms, Block-List.
4. **Settings**: Remains the same, holding Streams, Suppressions, Preference Topics.

### Implementation
1. Update `FeatureModules::Email::Registration` to only return 4 entries in the sidebar (Overview, Campaigns, Audience, Settings).
2. Create/update shared tabs partials for Overview and Campaigns.
3. Inject the new tabs partials into the Dashboard, Campaigns, Automations, Templates, and Assets views.
4. Update locales.
5. Fix tests.
