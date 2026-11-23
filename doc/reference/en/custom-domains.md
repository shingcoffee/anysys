---
title: "Custom domains"
summary: "Each customer has one optional domain, edited on the customer profile with the organization name. A new or changed domain requires a direct CNAME to anysys.net."
---

## Summary

Each customer stores at most one custom domain in `customers.domain`. A domain belongs to only one customer. The platform owner sets it on the customer create and edit form, in the Organization section, the same way as the organization name. The customer profile shows it there. Clearing the field removes the domain. There is no separate domain list, dedicated domain page, or manage-domains link.

Domains select the customer for public shortcut routing. They do not publish pages or change authorization. See [Customers](customers), [Tenancy and roles](tenancy-and-roles), and [Page shortcuts](page-shortcuts).

## Flow

```text
Platform owner + URL customer 81721200
  Maintenance → Platform → Customers → customer Edit
    Organization
      Organization name
      Domain
    Save changes
      blank → customers.domain = null
      unchanged → no DNS check
      new or changed → normalize → unique → direct CNAME anysys.net → write customers.domain
      invalid → 422 on the same profile form

Public request
  explicit eight-digit customer prefix → that customer
  otherwise exact domain → Customer.domain_owner_id
  otherwise → default customer 81721200
  selected inactive customer → 404, never another tenant
```

## Implementation

`customers.domain` is a nullable string, at most 253 characters, with a unique index. Blank means the customer has no custom domain. Before validation, `Customer` normalizes the value with `PageShortcuts::Hosts.normalize` (lowercase, IDN, no scheme, port, or path). An invalid value is rejected and the typed text stays on the form. `Customer.domain_owner_id` reads the column. There is no `customer_hostnames` table and no domain controller.

`customer_params` permits `:domain` with the other profile fields. Create and update use `Customer#save` / `#update`.

When the normalized domain is present and different from the stored value, save calls `CustomDomains::CnameVerifier.call(hostname:)`. The verifier returns `:verified` or `:unverified` and accepts only a direct answer-section CNAME to `anysys.net`. An alias chain does not pass. An unverified result adds `custom_domains.errors.cname_unverified` and does not change `domain`. Saving other profile fields, or clearing the domain, does not check DNS.

`PageShortcuts::Hosts.customer_id` and `dedicated?` read `Customer.domain_owner_id`. Inactive customers stay resolvable so public routing fails closed instead of falling through to another tenant. Lookups are uncached. Database failures are not converted into another tenant.

## Where to pay attention

:::attention
Soft-delete keeps `customers.domain`. Public requests for an inactive customer's domain return 404. Restore makes that domain routable again. Permanently deleting the customer deletes the domain with the row.
:::

:::attention
DNS, TLS, ingress, and Rails host authorization stay deployment concerns. Saving the domain records the binding. It does not admit the host to the Rails allowlist. The container that assumes SSL is described in [Docker image](docker-image).
:::

## Key code

```ruby
customer.update!(domain: "forms.acme.example")
```

```ruby
Customer.domain_owner_id("forms.acme.example")
```
