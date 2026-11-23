# Match the payments gateways' transport budget (Payments::Gateways::Base
# OPEN_TIMEOUT/READ_TIMEOUT): PSP calls must never hang a request thread.
# Credentials are NEVER configured globally — each tenant gets its own
# Stripe::StripeClient built from its MerchantAccount (see Payments::Gateways::Stripe).
Stripe.open_timeout = 5
Stripe.read_timeout = 30
