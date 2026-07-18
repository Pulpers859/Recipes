# Recipe Vault Share Extension

`RecipeVaultShare` accepts one web link, PDF, or image and writes it to the
shared App Group inbox. It does not parse recipes or access SwiftData, the AI
key, or any other app-only service. The main app always routes the item through
its normal import review flow.

The extension and app must both retain the App Group entitlement
`group.Patrick-App.Recipes`. `ShareInboxEnvelope.swift` is intentionally the
only app source compiled into both targets; it defines the on-disk protocol.

## Signing

The project declares the App Group in both entitlements files. Xcode automatic
signing must also register/enable that group for team `R4L58G49L2`. CI builds
without signing, so this one provisioning step can only be confirmed on a Mac
signed into the correct Apple Developer account.

## Device Smoke Test

1. Share a Safari recipe URL and confirm the Recipes-tab inbox banner appears.
2. Import it and confirm the ordinary review editor opens before anything is saved.
3. Repeat with a photo and with single- and multi-recipe PDFs.
4. Cancel multi-recipe review and confirm the shared PDF remains pending.
5. Fill the inbox to 20 items and confirm the extension refuses item 21.
