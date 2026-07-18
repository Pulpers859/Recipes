# Share Extension Staging

Pre-written source for the Recipe Vault share extension. This folder is
deliberately OUTSIDE both file-synchronized target roots (`Recipes/Recipes`
and `Recipes/RecipeVaultTests`) so nothing here is compiled yet — synchronized
folders auto-compile every `.swift` file they contain, and this code needs a
target that can only be created in Xcode.

**Status: staged, not compiled.** The app-side half of the feature (inbox
reader, Import screen section, Recipes-tab banner) already ships in the app
and is dormant: `ShareInbox.inboxDirectory()` returns nil until the App Group
entitlement below exists, so every code path no-ops.

## Phase B — one sitting on the Mac (~30–60 min)

1. Open `Recipes.xcodeproj`. File → New → Target → **Share Extension**.
   - Product name: `RecipeVaultShare`. Language Swift, no SwiftUI needed.
   - Do NOT activate the scheme it offers, keep using the `Recipes` scheme.
2. Delete the template's `ShareViewController.swift` (it subclasses
   `SLComposeServiceViewController`; ours doesn't) and drag this folder's
   `ShareViewController.swift` into the extension's folder instead.
3. Extension `Info.plist`, replace the `NSExtension` dict with:

   ```xml
   <key>NSExtension</key>
   <dict>
     <key>NSExtensionAttributes</key>
     <dict>
       <key>NSExtensionActivationRule</key>
       <dict>
         <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
         <integer>1</integer>
         <key>NSExtensionActivationSupportsImageWithMaxCount</key>
         <integer>1</integer>
         <key>NSExtensionActivationSupportsFileWithMaxCount</key>
         <integer>1</integer>
         <key>NSExtensionActivationSupportsText</key>
         <true/>
       </dict>
     </dict>
     <key>NSExtensionPointIdentifier</key>
     <string>com.apple.share-services</string>
     <key>NSExtensionPrincipalClass</key>
     <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
   </dict>
   ```

   Note the dictionary keys are OR'd: "file with max count 1" activates for
   any file type, not just PDFs — the controller answers non-PDF files with a
   polite error. Tightening this to a SUBQUERY predicate is optional polish.
4. Signing & Capabilities — on **both** the `Recipes` app target and the new
   `RecipeVaultShare` target — add capability **App Groups** with
   `group.Patrick-App.Recipes` (must match `ShareInbox.appGroupIdentifier`).
5. Share `ShareInboxEnvelope.swift` with the extension: select
   `Recipes/Recipes/Service/ShareInboxEnvelope.swift` in the navigator →
   File Inspector → Target Membership → also check `RecipeVaultShare`.
   (That file is the entire contract; the extension must NOT get
   `ShareInboxService.swift` or anything else from the app.)
6. Match the extension's iOS deployment target to the app's.
7. Build and run on the phone, then smoke test:
   - Safari → share a recipe page → Recipe Vault → banner appears on the
     Recipes tab → Import → review sheet shows the scraped recipe.
   - Photos → share a recipe photo → same flow (OCR/AI parse).
   - Files → share a PDF (single- and multi-recipe) → same flow; the
     multi-recipe case must open batch review, and cancelling that review
     must leave the shared item in the Import screen's list.
   - Share while the inbox already has 20 items → extension refuses politely.

## Contract reminders

- Payload file first, envelope (`<uuid>.envelope.json`) last — the envelope
  is the commit marker. Never write an envelope for a payload that isn't
  fully on disk.
- The extension never parses, never opens SwiftData, never touches the
  Keychain. It stores bytes and exits.
- `ShareInboxTests.swift` in `RecipeVaultTests` pins the protocol from both
  sides (writer via `ShareInbox.writeItem`, reader via `ShareInboxService`);
  it runs on CI and on the Windows harness.
