---
name: submit
description: Create the App Store version, write release notes, attach the build, and submit for review
disable-model-invocation: true
---

# Submit to App Store review

Take a build that is already uploaded to App Store Connect and turn it into a submitted release:
create the version record, write "What's New" for every locale, attach the build, validate, submit.

`/ship` runs this automatically as its Step 11. Run it standalone when a build was uploaded earlier
without being submitted, when a submission was rejected and needs re-sending, or when a `/ship` run
uploaded fine but its submit step failed.

Constants (same as `ship`): app id `6760177675`, platforms `MAC_OS` / `IOS`, tag scheme
`v<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>`. `asc` authenticates on its own from the system
keychain — see `asc auth doctor` if it errors.

**Everything below runs per platform.** macOS and iOS share one `MARKETING_VERSION` but have
independent version trains, independent `appStoreVersions` records, and independent review
submissions. A failure on one platform must not stop the other.

## Arguments

- `/submit`, `/submit both` — both platforms (default)
- `/submit ios`, `/submit mac` — one platform
- `/submit 4.8` — a marketing version

A platform word (`ios`, `mac`, `macos`, `both`) selects the platform — it is **not** a version. Only
treat an argument as a marketing version if it looks like one (`4.8`, `4.8.1`).

## Step 1: Resolve the version and the build

Version = the argument if given, else `MARKETING_VERSION` from `screenshot.xcodeproj/project.pbxproj`.

```bash
asc builds info --app 6760177675 --latest --platform MAC_OS --version "<MV>"
asc builds info --app 6760177675 --latest --platform IOS   --version "<MV>"
```

Record the build `id` per platform. Require `processingState: VALID`:

- `PROCESSING` → block on `asc builds wait --app 6760177675 --latest --platform <P>`, then re-read.
- No build for that version on a selected platform → **stop for that platform** and report it. That
  platform was never uploaded; run `/ship <platform>` first.

Also note `encryption` — it should read `exempt` (the app sets `ITSAppUsesNonExemptEncryption` in
`ScreenshotBro-Info.plist`). Anything else blocks submission and needs a declaration.

## Step 2: Ensure an editable version record exists

```bash
asc versions list --app 6760177675 --platform <P> --limit 5
```

- A record for `<MV>` exists in an **editable** state (`PREPARE_FOR_SUBMISSION`,
  `DEVELOPER_REJECTED`, `REJECTED`, `METADATA_REJECTED`) → reuse its id, skip to Step 3.
- A record for `<MV>` exists in a **released or in-review** state (`READY_FOR_DISTRIBUTION`,
  `READY_FOR_SALE`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`) → stop for that
  platform and report it. Either it is already submitted, or the version is spent and shipping needs
  a higher `MARKETING_VERSION` (that is `/ship` Step 2b's job, not this skill's).
- No record → create one, carrying the previous release's metadata but **not** its "What's New":

```bash
asc versions create --app 6760177675 --version "<MV>" --platform <P> \
  --release-type AFTER_APPROVAL \
  --copy-metadata-from "<previous version string>" --exclude-fields "whatsNew"
```

`AFTER_APPROVAL` means the version goes live the moment Apple approves it — no manual release step.
`--copy-metadata-from` (the newest released version on that platform, e.g. `4.7`) carries
description / keywords / promotionalText / marketingUrl / supportUrl across all 16 locales. App Store
Connect itself carries screenshots, App Review details and copyright onto a new version — confirmed
on the 4.7 → 4.8 run, where `asc validate` came back with zero findings on both platforms — but Step 5
is the gate, so don't assume it. Fixes if it does flag them:

```bash
# App Review details (contact info + the demo-mode reviewer note)
asc review details-for-version --version-id "<PREV_VID>" --pretty
asc review details-create --version-id "<VID>" \
  --contact-first-name "…" --contact-last-name "…" --contact-email "…" --contact-phone "…" \
  --notes "…"

# Copyright
asc versions update --version-id "<VID>" --copyright "…"
```

## Step 3: Write "What's New"

The range is the previous ship tag to this one — the same pair `/ship` Step 9 computes for Sentry:

```bash
CUR=$(git describe --tags --abbrev=0)            # e.g. v4.8-121
PREV=$(git describe --tags --abbrev=0 "$CUR^")   # e.g. v4.7-120
git log --oneline "$PREV..$CUR"
```

Read that log and write a **short user-facing summary** — what a customer would notice. Not commit
subjects, not refactors, not test or tooling work. A few lines is right; the ASC limit is 4000
characters. If nothing user-visible changed, use the literal fallback:

```
New features and bug fixes
```

Apply the same English text to every locale the version carries — read them, don't hardcode:

```bash
asc localizations list   --version "<VID>" --output table
asc localizations update --version "<VID>" --locale "<L>" --whats-new "<text>"
```

Loop over the locales one call at a time. The shell here is **zsh**, which does not word-split an
unquoted `$LOCALES`, so a naive `for L in $LOCALES` passes the whole list as one locale and every
call fails — pipe the list into `while read -r L` instead.

There are 16 today (`ar-SA da de-DE en-US es-ES fi fr-FR he it ja ko nl-NL no pt-PT sv zh-Hans`) and
they all carry the same English string, so this matches existing practice. Use exact ASC locale
codes — `ar-SA` not `ar`, `de-DE` not `de`, `zh-Hans` not `zh-Hans-CN`
(`asc localizations supported-locales --version "<VID>"` if unsure).

**Don't touch descriptions here.** That is `/update-app-store-descriptions`, which writes into
whichever `PREPARE_FOR_SUBMISSION` version exists — so running it *after* Step 2 and before Step 5 is
how a description change rides along with this release.

## Step 4: Attach the build

```bash
asc versions attach-build --version-id "<VID>" --build-id "<BID>"
```

`asc review submit` in Step 6 can do this too, but attaching explicitly keeps an attach failure
distinguishable from a submission failure.

## Step 5: Validate — this is the gate

```bash
asc validate --app 6760177675 --version-id "<VID>"
```

It checks metadata lengths, required localizations, review details, primary category, build attached
and processed, encryption declaration, content rights, pricing and territory availability, screenshot
presence and sizes, and age rating — and returns an ordered remediation plan whose first item is the
next thing to fix.

**Any blocking issue: stop, print the plan, do not submit.** Apply the Step 2 fixes where they apply,
re-validate, then continue. `asc review doctor --app 6760177675` gives the app-scoped view when
`validate` is ambiguous.

One `info` finding is expected on every run and is **not** blocking: `privacy.publish_state.unverified`
("App Privacy publish state is not verifiable via the public App Store Connect API"). App Privacy is
published for this app; the public API simply can't report it. A clean run is `Errors 0 / Warnings 0 /
Blocking 0` with that single info.

## Step 6: Submit for review

```bash
asc review submit --app 6760177675 --version-id "<VID>" --build "<BID>" --confirm
```

One call per platform. It wraps `versions attach-build` + `review submissions-create` +
`review items-add` + `review submissions-submit`. When debugging a failure, re-run with `--dry-run`
and no `--confirm` to see the plan without mutating.

## Step 7: Report

```bash
asc status --app 6760177675 --platform <P> --include appstore,submission,review
```

Print per platform: version id, whether the record was created or reused, build attached, submission
id, and submission state (expect `WAITING_FOR_REVIEW`). Print the "What's New" text once, not per
platform. State the release type (`AFTER_APPROVAL` — goes live automatically on approval).

Undo, if something went out wrong:

```bash
asc review submissions-cancel --id "<SID>" --confirm
asc versions delete --version-id "<VID>"    # only while PREPARE_FOR_SUBMISSION
```
