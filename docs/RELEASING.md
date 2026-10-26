# Releasing

How a version goes from `main` to users: GitHub Release assets (APK + AAB),
the Google Play open testing track, and later production. iOS delivery is not
automated yet (see the end of this page).

## Single source of truth for release notes

The store copy for a release lives in one place:

```
fastlane/metadata/android/en-US/changelogs/default.txt
```

Everything else is derived from it:

| Consumer | How it gets the text |
|---|---|
| Google Play "What's new" | `fastlane android open_testing` uploads it with the AAB (supply) |
| GitHub Release body | CI appends a `## Store release notes` block via `scripts/release-notes.sh` |
| Release PR body | You paste the same block under `## Store release notes` (PR template) |

Rules:

- Edit `default.txt` in the release PR, never in the Play Console.
- Keep it under 500 characters (Play limit) and plain text, no markdown.
- To pin notes to a specific build, add `<versionCode>.txt` next to
  `default.txt` (for example `3.txt` for `0.2.0+3`). Both supply and the
  script prefer that file and fall back to `default.txt`.
- Print the block locally with `scripts/release-notes.sh`.

Listing copy (title, short and full descriptions) for all seven locales is
mirrored under `fastlane/metadata/android/<locale>/`. It is not uploaded by
the release flow. Push it deliberately with `fastlane android sync_listing`.

## Release flow

1. **Bump the version** in `pubspec.yaml` (`X.Y.Z+N`; bump `N` on every
   Play upload, Play rejects a reused versionCode).
2. **Update the release notes** in
   `fastlane/metadata/android/en-US/changelogs/default.txt`.
3. **Open the release PR.** The body must include a `## Store release notes`
   section with the same text. CI must be green.
4. **Merge** to `main`.
5. **Publish a GitHub Release** tagged `vX.Y.Z` on the merge commit
   (`gh release create vX.Y.Z --generate-notes`). Publishing triggers
   `.github/workflows/release.yml`, which:
   - runs analyze and tests;
   - builds the signed AAB and APK (needs the `ANDROID_*` signing secrets);
   - uploads both as workflow artifacts and attaches them to the Release;
   - appends the `## Store release notes` block to the Release body;
   - uploads the AAB to the Play **open testing** track with the changelog
     (needs `PLAY_SERVICE_ACCOUNT_JSON`; skipped with a log line otherwise).
6. **Test the open testing build** from the Play listing or the testers
   link in the Play Console.
7. **Promote to production** when ready. Either click Promote in the Play
   Console, or run locally:

   ```
   export PLAY_SERVICE_ACCOUNT_JSON_PATH=/path/to/service-account.json
   cd android && bundle exec fastlane android promote_production
   ```

   CI never promotes. Production rollout stays a human decision.

Manual runs of the workflow (`workflow_dispatch`) build and upload artifacts
only; they never touch Play or the Release body.

## Required secrets

| Secret | Used for |
|---|---|
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Signing the AAB and APK; see [BUILDING.md](BUILDING.md) for how the keystore is made |
| `PLAY_SERVICE_ACCOUNT_JSON` | Uploading to Google Play |

### Creating `PLAY_SERVICE_ACCOUNT_JSON`

1. Play Console: **Setup** then **API access**. Link a Google Cloud project if
   asked.
2. Under **Service accounts**, choose **Create new service account** and
   follow the link to the Google Cloud console. Create the account (any
   name, for example `play-ci`). No Cloud roles are needed.
3. In the Cloud console, open the account, **Keys**, **Add key**,
   **Create new key**, type JSON. Download the file.
4. Back in Play Console API access, click **Manage Play Console permissions**
   for the new account. Grant the app `org.motherofallvpns.moavdeploy`
   with the **Release manager** permission set (release to testing tracks,
   manage production releases, edit store listing). Save and invite.
5. Add the JSON to the GitHub repo as secret `PLAY_SERVICE_ACCOUNT_JSON`.
   Raw JSON and base64 are both accepted:

   ```
   gh secret set PLAY_SERVICE_ACCOUNT_JSON < service-account.json
   ```

6. Delete the local copy of the JSON when done. Never commit it.

Validate a key without uploading anything:

```
export PLAY_SERVICE_ACCOUNT_JSON_PATH=/path/to/service-account.json
cd android && bundle exec fastlane run validate_play_store_json_key json_key:"$PLAY_SERVICE_ACCOUNT_JSON_PATH"
```

Note: a brand-new app must have its first AAB uploaded by hand in the Play
Console before the API will accept uploads.

## Running fastlane locally

```
bundle install
flutter build appbundle --release          # needs android/key.properties
export PLAY_SERVICE_ACCOUNT_JSON_PATH=/path/to/service-account.json
cd android
bundle exec fastlane lanes                 # list lanes
bundle exec fastlane android open_testing      # same as CI
```

Lanes (`android/fastlane/Fastfile`):

| Lane | What it does | Who runs it |
|---|---|---|
| `android open_testing` | Upload the signed AAB to the open testing track, status completed, with the changelog | CI on release publish |
| `android promote_production` | Promote the current open testing release to production | Humans only |
| `android sync_listing` | Push title and descriptions for all locales from `fastlane/metadata` | Humans only |
| `ios beta` | Stub. Prints a notice; nothing is uploaded | Nobody yet |

## iOS

The iOS lane is a stub until the Apple developer account and App Store
Connect API key are set up. Until then, build with `flutter build ipa` and
upload through Xcode or Transporter (see [DISTRIBUTION.md](DISTRIBUTION.md)).
