# Privacy Policy

**Poker HUD**
*Last updated: April 13, 2026*

## Overview

Poker HUD ("the App") is a macOS application that helps poker players track and analyze their hand histories. Your privacy is important to us. This Privacy Policy explains what data the App collects, how it is used, and your rights regarding that data.

## Data We Collect

### Account Information
- **Email address and password** — used to create and authenticate your account via Supabase Auth. Your password is stored as a salted bcrypt hash; we never store or have access to your plaintext password.

### Subscription Data
- **Subscription status, plan type, and transaction identifiers** — stored on our server to verify your entitlement. Payment processing is handled entirely by Apple through StoreKit; we do not collect or store credit card numbers or billing details.

### Usage Data
- **Hands imported count** — tracked locally and on the server to manage the free trial limit.

### Poker Hand History Data
- **Hand history files** — parsed and stored **locally on your Mac** in a SQLite database. Hand history data is never uploaded to our servers.

### Accessibility Data
- The App uses the macOS Accessibility API solely to detect and overlay HUD statistics on poker table windows. No screen content is captured, recorded, or transmitted.

## How We Use Your Data

- **Authentication**: To sign you in and manage your account.
- **Subscription verification**: To determine whether you have an active subscription.
- **Statistics and analytics**: All poker statistics are computed and stored locally on your device for your personal use.
- **HUD overlay**: To position stat overlays on poker table windows.

We do **not** use your data for advertising, profiling, or selling to third parties.

## Third-Party Services

| Service | Purpose | Data Shared | Privacy Policy |
|---------|---------|-------------|----------------|
| Apple (StoreKit) | Subscription payments | Transaction IDs | [Apple Privacy](https://www.apple.com/privacy/) |
| Supabase | Authentication & subscription storage | Email, hashed password, subscription status | [Supabase Privacy](https://supabase.com/privacy) |

## Data Storage and Security

- **Local data**: Hand histories and statistics are stored in a local SQLite database on your Mac (`~/Library/Application Support/PokerHUD/poker.db`). This data never leaves your device.
- **Server data**: Account and subscription information is stored on Supabase infrastructure hosted in the EU (eu-west-1) with encryption at rest and in transit.
- **App Sandbox**: The App runs within the macOS App Sandbox, limiting its access to only the files and resources you explicitly grant.

## Data Retention

- **Account data** is retained as long as your account is active.
- **Local hand history data** is stored on your device and can be deleted at any time from the App's Settings.
- If you delete your account, your server-side data (email, subscription records, usage counters) will be permanently removed.

## Your Rights

You have the right to:

- **Access** your data by viewing your statistics and account information within the App.
- **Delete** your local data at any time via Settings > Database > Clear All Data.
- **Delete your account** and all associated server-side data by contacting us at the email below.
- **Export** your data using the App's built-in CSV/JSON/PDF export feature.

## Children's Privacy

The App is not intended for use by anyone under the age of 18. We do not knowingly collect data from minors.

## Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be posted to this page with an updated revision date. Continued use of the App after changes constitutes acceptance of the updated policy.

## Contact

If you have questions about this Privacy Policy or wish to exercise your data rights, please contact us at:

**Email**: support@pokerhud.app
**GitHub**: [https://github.com/matteocaglio1989-cmd/Poker-HUD/issues](https://github.com/matteocaglio1989-cmd/Poker-HUD/issues)
