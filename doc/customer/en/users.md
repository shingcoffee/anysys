---
title: "Add and manage users"
summary: "Give colleagues the right access, keep account details current, and help users recover secure sign-in."
---

## Before you start

Sign in as an administrator and confirm that **Users** is available. It requires the user authentication module. Have the person's name, email address, and intended access ready.

An **Admin** manages resources within your organization. A **Member** uses their own account, profile, and member records. Give administrator access only to people who need those responsibilities. The service owner's reserved access is not an assignable customer role.

## Steps

### Create an account

1. Open **Users**, or **Modules → User Authentication → Users**.
2. Select **New User** and complete the fields:
   1. Enter the person's first name, last name, and email. For example, use `alex@example.com` only if it is the person's actual intended account address.
   2. Enter a password of at least eight characters and repeat it in **Confirm password**.
   3. Choose **Admin** or **Member** according to their responsibilities.
3. Select **Create User**. Correct any highlighted validation errors before submitting again.
4. Search for the saved email and open the account. Check its name, role, and status.

:::note
Admin-created accounts are confirmed during creation. Creating an account is not an invitation-email action; arrange how the person will receive access. Member self-registration is controlled separately in **Settings → Member registration**.
:::

### Update account details

1. Find the user by name or email; narrow the list with role or status filters if needed.
2. Open the account and select **Edit**.
3. Change only the required fields. Leave password and confirmation blank to retain the existing password. Supply your current password when requested for changes to your own account.
4. Select **Update User**, then reopen the details and verify the saved name, email, and role.

### Deactivate or restore access

1. On a user's details page, review their role, MFA state, sign-in activity, and trusted devices.
2. Use **Deactivate** when the person should no longer sign in. Use **Activate** to restore access when appropriate. You cannot deactivate your own account.
3. Confirm the resulting account status before telling the person to sign in again.

### Reset MFA or revoke a trusted device

1. Open the user's details. If they have lost their authenticator, verify their identity, then select **Reset MFA** and read the confirmation. Ask another administrator to reset your own MFA.
2. Check that the account no longer shows enrolled MFA; the user must set it up again when required. A reset does not change their role.
3. Under **Trusted Devices**, select **Revoke** for the specific device they no longer recognize or use. Confirm that it disappears from the list; that device must complete two-step verification at its next sign-in when required.
4. Open **Modules → User Authentication → Security Log** to review sign-ins and security changes. Filter the time range or search by IP address or device.

## What to expect

Changes apply to accounts in your organization. Deactivation prevents sign-in; it does not delete the user record. MFA and trusted-device actions change sign-in protection, not access scope.

Built-in roles have defined access scopes. **Settings → User access** and **Roles & permissions** let you review existing access; read-only permissions cannot be edited there.

## Troubleshooting

- **Creation is rejected:** correct the highlighted fields, check whether the email is already used, and review any plan-limit message.
- **The user cannot sign in:** check account status, registration or recovery settings, and MFA requirements before changing their role.
- **Changing your own email or password fails:** supply the current password when requested.
- **Users is missing:** contact support to check module availability.

## Related guides

- [Getting started](getting-started)
- [Settings](settings)
- [Billing](billing)
- [Support](support)
