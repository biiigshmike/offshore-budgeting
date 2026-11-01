# Tip Jar setup and release checklist

Settings → Support & Feedback → Tip Jar uses StoreKit 2 consumable purchases.
Tips are optional, repeatable, and grant no features. They never enter a workspace's
financial records. Prices and names come from Apple, including localized currencies.
No payment server, external checkout, or restore entitlement is needed for these tips.

## App Store Connect

1. As Account Holder, open Business and accept the Paid Apps Agreement. Complete
   required banking and tax information. The app itself stays free.
2. Apply separately for the App Store Small Business Program if eligible; wait for
   approval rather than assuming the reduced commission already applies.
3. In My Apps → Offshore Budgeting → Monetization → In-App Purchases, create these
   three products, each with type **Consumable**. Product IDs must match exactly:

| Reference name / English display name | Product ID | US base price |
| --- | --- | --- |
| Small Tip | `com.mb.offshore_budgeting.tip.small` | USD 0.99 |
| Medium Tip | `com.mb.offshore_budgeting.tip.medium` | USD 2.99 |
| Large Tip | `com.mb.offshore_budgeting.tip.large` | USD 4.99 |

4. Set United States as the base country/region, choose each price, review Apple's
   converted prices, and select availability for the countries you support.
5. Add localizations. Suggested description for each:
   “An optional one-time tip to support Offshore. Does not unlock features.”
6. Complete the required tax category and review information. Upload a screenshot
   of the Tip Jar screen and explain where reviewers can find it. Do not enable
   Family Sharing or configure subscriptions; these are consumables.
7. In Xcode, check the main app target's Signing & Capabilities for In-App Purchase
   and add it if absent. Use automatic signing with your normal developer team.
8. Upload a new app build. On the new version's page, attach all three products in
   In-App Purchases and Subscriptions. The first consumables must be submitted
   with a new app version. Submit the version and products together.

Suggested review notes:

> The optional Tip Jar is at Settings → Support & Feedback → Tip Jar. All three
> consumable purchases are voluntary tips to the developer. They grant no content,
> feature access, currency, or subscriptions. The entire app remains free. Each tip
> may be purchased repeatedly.

## Verify before submission

- In Xcode, create a StoreKit Configuration File with three consumables matching
  the table. Set the scheme's Run → Options → StoreKit Configuration to that file
  for local testing. Use the same names and prices as above.
- Verify all three amounts and repeat a successful tip. Confirm a thank-you appears.
- Cancel the Apple sheet: no thank-you or error should appear.
- Simulate failed purchases, disabled purchasing, unavailable products, and offline
  loading. Verify errors/retry and that other app functions remain usable.
- Simulate Ask to Buy; approve while running and after relaunch. Confirm the
  transaction is finished without granting an entitlement or changing financial data.
- Check localized currency, large Dynamic Type, and VoiceOver.
- Then disable the local StoreKit configuration and test real App Store Connect
  products using Sandbox/TestFlight. TestFlight IAP uses sandbox, not real charges.
- Confirm products are approved and available before release. Until configured,
  the screen shows an unavailable message and Retry rather than fabricated prices.

## References

- https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/
- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase
- https://developer.apple.com/app-store/small-business-program/
