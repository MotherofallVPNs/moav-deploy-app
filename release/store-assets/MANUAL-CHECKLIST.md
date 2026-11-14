# Manual checklist: first public release (0.2.15, build 18)

What has to be done by hand in App Store Connect and the Play Console, in
order. Everything that could be prepared ahead is ready; each step says
which file to take the value from.

The files live in two places:

- `compliance/` and `tool/` are in this folder.
- `copy/`, `screenshots/` and `branding/` are in the private
  [moav-store-assets](https://github.com/MotherofallVPNs/moav-store-assets)
  repo. Clone it next to this repo before you start (see
  [README.md](README.md)).

Nothing in this package has been pushed to either store. No version was
bumped and no track was touched.

## 0. Decide first (these change what you submit)

- [ ] **Read the copy and look at the screenshots** in `moav-store-assets`.
      Edit `copy/*.md` there and `tool/captions.json` here if anything is
      off, then rerun the tools (see [README.md](README.md)) and commit the
      results in `moav-store-assets`.
- [ ] **Money donation links.** The "Support us" sheet opens Stripe, GitHub
      Sponsors and Buy Me a Coffee in the browser. Both stores can object
      (details in [compliance/review-notes.md](compliance/review-notes.md),
      risk 1). Choose: submit 0.2.15 as is, or ship a 0.2.16 that hides
      them on iOS first.
- [ ] **France on the App Store.** The app carries its own SSH crypto, which
      Apple ties to a French encryption declaration. Choose: leave France
      out for now, or file the declaration
      ([compliance/export-compliance.md](compliance/export-compliance.md)).
- [ ] **China mainland.** Recommended: exclude on both stores.
- [ ] **Apple account type.** Confirm the developer account is enrolled as
      an organisation (matters only if review treats the app as a VPN app).

## 1. Push the text by API (optional, saves most of the typing)

Run after the copy is approved. Needs the App Store Connect key and Play
service-account env vars from `docs/RELEASING.md`, and the
`moav-store-assets` checkout: `check_copy.py` reads `copy/*.md` from it
(a sibling checkout, or the path in `MOAV_STORE_ASSETS`).

```
python3 release/store-assets/tool/check_copy.py --apply   # writes fastlane/metadata (en-US)
git diff fastlane/metadata                                # review, then commit
cd android
bundle exec fastlane ios sync_metadata        # name, subtitle, description, keywords, promo text, URLs, categories
bundle exec fastlane android sync_listing     # Play title and descriptions, all locales
```

`sync_metadata` edits the draft version in App Store Connect; nothing goes
live until you submit. `sync_listing` updates the Play store listing, which
Google reviews before it shows. If you would rather paste by hand, skip this
section and use the fields in `copy/app-store.md` and `copy/google-play.md`
in `moav-store-assets`.

Images are not pushed by either lane. Upload them by hand below.

## 2. App Store Connect

App: MoaV Deploy, bundle id `org.motherofallvpns.moavdeploy`.

### App Information

- [ ] Name and subtitle: `copy/app-store.md` (skip if pushed in step 1)
- [ ] Category: Utilities (primary), Developer Tools (secondary)
- [ ] Content rights: "No, it does not contain, show, or access third-party
      content"
- [ ] Age rating: answers in `compliance/review-notes.md`, section Content
      rating. Expected 4+

### Pricing and Availability

- [ ] Price: Free
- [ ] Countries: all, minus China mainland, minus France if you chose to
      defer the declaration
- [ ] EU Digital Services Act: declare trader status (Business section of
      App Store Connect). Apple will not distribute in the EU without it.
      A trader declaration publishes an address, phone and email on the
      listing, so decide which contact details to use

### App Privacy

- [ ] Privacy policy URL: `https://moav.sh/docs/deploy/privacy/`
- [ ] Data collection: "No, we do not collect data from this app", then
      Publish. Reasoning in `compliance/privacy.md`

### Version 0.2.15 (Prepare for Submission)

- [ ] Screenshots, drag each folder from `moav-store-assets` into its slot:
  - iPhone 6.9" display: `screenshots/ios/iphone-6.9/` (10 files, 1290x2796)
  - iPhone 6.5" display: `screenshots/ios/iphone-6.5/` (10 files, 1242x2688)
  - iPad 13" display: `screenshots/ios/ipad-12.9/` (10 files, 2048x2732)
- [ ] Promotional text, description, keywords, support URL, marketing URL,
      copyright: `copy/app-store.md` (skip if pushed in step 1)
- [ ] Build: select 0.2.15 (18) from TestFlight. Export compliance shows as
      already answered (the Info.plist key)
- [ ] App Review Information:
  - Sign-in required: off
  - Contact: your name, phone and email (Apple calls or emails this person)
  - Notes: paste the block from `compliance/review-notes.md`
- [ ] Version release: "Manually release this version", so approval does not
      publish the app before you are ready
- [ ] Add for Review, then Submit

The app icon is taken from the build, not uploaded. `branding/ios-app-icon-1024.png`
is the same image, kept for press and web use.

## 3. Google Play Console

App: MoaV Deploy, package `org.motherofallvpns.moavdeploy`.

### Grow, Store presence, Main store listing

Text and images come from `moav-store-assets`.

- [ ] App name, short description, full description: `copy/google-play.md`
      (skip if pushed in step 1)
- [ ] App icon: `branding/play-icon-512.png`
- [ ] Feature graphic: `branding/play-feature-graphic-1024x500.png`
- [ ] Phone screenshots: `screenshots/android/phone/` (8 files, 1080x1920)
- [ ] Tablet screenshots: none prepared. Optional; Play only uses them to
      feature the app on tablets

### Store settings

- [ ] App category: Tools. Tags: pick the closest network or developer tags
- [ ] Contact details: `info@moav.sh`, `https://moav.sh`

### Policy, App content

All answers are in `compliance/privacy.md` and `compliance/review-notes.md`.

- [ ] Privacy policy: `https://moav.sh/docs/deploy/privacy/`
- [ ] Ads: no ads
- [ ] App access: all functionality available without special access, with
      the demo-server note
- [ ] Content rating: IARC questionnaire, expected Everyone / PEGI 3
- [ ] Target audience: 18 and over
- [ ] Data safety: no data collected, no data shared
- [ ] Advertising ID: not used
- [ ] News, government, financial features, health: no / none

### Production release

- [ ] If the account is a personal one created after November 2023, confirm
      production access has been granted (the closed-test requirement of 12
      testers for 14 days). The Production page says so if it has not
- [ ] Check the pre-launch report for versionCode 18 on the testing track:
      no blocking warnings
- [ ] Publishing overview: turn on Managed publishing if you want to choose
      the go-live moment yourself
- [ ] Production, Countries / regions: add countries (all, minus China if
      you decided so)
- [ ] Production, Create new release: promote versionCode 18 from the
      testing track ("Promote release" on the open testing page, or
      `bundle exec fastlane android promote_production` from `android/`)
- [ ] Release notes: keep the existing line or paste the first-release
      draft from `copy/google-play.md`
- [ ] Choose a staged rollout percentage or 100%, then Send for review

## 4. After both are approved

- [ ] Release the iOS version (manual release button) and publish the Play
      changes if Managed publishing is on
- [ ] Update the README badges: Google Play "open testing" and the
      TestFlight badge become store links
- [ ] Mark the stores as published in `docs/DISTRIBUTION.md`

## Not done here, on purpose

- No store API call was made; the text and images wait for your review in
  `moav-store-assets`.
- The listing images and copy are not in this repo. They stay in the
  private `moav-store-assets` repo.
- The six non-English Play listings keep their current translations.
- `fastlane/metadata/` was not modified; `check_copy.py --apply` does that
  when you run it. The screenshots under `fastlane/metadata/*/` are the
  older pre-demo set, used only by F-Droid metadata.
