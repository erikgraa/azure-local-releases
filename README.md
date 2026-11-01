# Azure Local Lifecycle

Keep on top of your Azure Local releases and when support ends. A static site that lists every [Azure Local](https://learn.microsoft.com/en-us/azure/azure-local/) release with its release date and end of support date. It is rebuilt daily from [Microsoft's release information](https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2) and hosted on GitHub Pages at https://lifecycle.azl.graa.dev/ (repository: `azure-local-releases`).

[![Build and deploy site](https://github.com/erikgraa/azure-local-releases/actions/workflows/pages.yml/badge.svg)](https://github.com/erikgraa/azure-local-releases/actions/workflows/pages.yml)

> [!IMPORTANT]  
> This tool only covers generic Azure Local releases as parsed from [Microsoft's documentation](https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2). Please verify with specific OEM hardware vendors' documentation for supported installation/upgrade paths according to their particular compatibility matrices

## ✨ What's new

This repository used to offer a PowerShell cmdlet and a [Pode](https://badgerati.github.io/Pode) API hosted as an Azure Container App. It is now a static site on GitHub Pages:

- **Static site "Azure Local Lifecycle"**: a plain, table-first page (in the spirit of the old Pode page) with the recommended release, the next end of support, a "Which version are you running?" checker and a table of releases with status and days left, all driven by the generated JSON data.
- **Feeds**: an RSS feed, a JSON Feed, an end of support calendar (ICS) and a JSON data file (plus the plain JSON array that was already committed here).
- **Safe by design**: generated files are validated before anything is published, so a broken parser can never replace good data with empty or partial data, and the owner is alerted through a GitHub issue when a run fails, see [Failure protection and alerts](#failure-protection-and-alerts).
- **Fixed cmdlet and parser**: `Get-AzureLocalRelease` had stopped working because Microsoft changed the layout of the release documentation (the committed JSON had not been updated since February 2026). The parser has been rewritten for the current layout and now also handles builds that supersede earlier ones.
- **End of support dates** derived from Microsoft's six-month support policy, see [How end of support is determined](#how-end-of-support-is-determined).
- **Daily automatic refresh** through a GitHub Actions workflow, see [Deployment](#deployment).
- **Removed**: the Pode app, the `Dockerfile`, the container app workflow and the query API, see [What was removed](#-what-was-removed).

## 🎬 Site

Live at https://lifecycle.azl.graa.dev/.

[![Azure Local releases site](/assets/demo.png)](https://lifecycle.azl.graa.dev/)

- **At a glance**: the release recommended for new deployments (with its end of support date) and the next release to reach end of support, with days left
- **Version checker**: pick the version you run and see when it goes out of support, or that it already has, and what to update to
- **Releases table**: release, version, release date, end of support date and a status (**Supported**, **Ending soon** within 60 days, **End of support**) with the time left. Retired releases are hidden unless you tick *Show retired*.
- **Row details**: click a row for the release's top feature highlights (with a *Preview* marker), the OS build, earlier builds that the release superseded and links to what's new, security updates, known issues and the solution update ZIP
- **Search and filters**: search by version, release train or OS build and filter by OS version (24H2/23H2). The view is kept in the URL so it can be shared.
- Feed links (RSS, JSON Feed, Calendar, JSON) in the header, and a short note on subscribing to the end of support calendar
- Follows your light or dark system theme, with a mobile layout and an icon (`favicon.svg`, light and dark aware) plus a social share image
- Works offline once loaded: a small service worker caches the site and data (network first, so it never serves stale data when online). Status and days left are calculated in the browser, so they stay correct between daily data refreshes. The footer shows when the data last changed (a daily run without changes writes nothing).

## 📡 Feeds and data

| Artifact | URL |
| --- | --- |
| RSS 2.0 feed of new releases | https://lifecycle.azl.graa.dev/feed.xml |
| JSON Feed 1.1 of new releases | https://lifecycle.azl.graa.dev/feed.json |
| End of support calendar (ICS) | https://lifecycle.azl.graa.dev/calendar.ics |
| The same calendar with reminders | https://lifecycle.azl.graa.dev/calendar-reminders.ics |
| Releases and release trains as JSON | https://lifecycle.azl.graa.dev/data/releases.json |
| Plain array of releases (also committed to this repository) | [json/azure-local-releases.json](json/azure-local-releases.json) |

`data/releases.json` looks like this:

```json
{
  "generatedAt": "2026-10-31T06:00:00Z",
  "source": "https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2",
  "supportPolicy": { "days": 180, "description": "..." },
  "newDeployments": [ "12.2610.1004.41" ],
  "trains": [ { "releaseTrain": "2610", "osVersions": [ "24H2" ], "firstAvailabilityDate": "2026-10-22", "endOfSupportDate": "2027-04-20", "supported": true, "versions": [ "12.2610.1004.41" ] } ],
  "releases": [
    {
      "version": "12.2610.1004.41",
      "availabilityDate": "2026-10-22",
      "firstAvailabilityDate": "2026-10-22",
      "newDeployments": true,
      "osBuild": "26100.33650",
      "osVersion": "24H2",
      "releaseTrain": "2610",
      "release": "2610.1004.41",
      "releaseShortened": "2610.1004",
      "baselineRelease": true,
      "endOfSupportDate": "2027-04-20",
      "supported": true,
      "supersedes": [],
      "features": [
        { "title": "Rack aware clusters with SAN", "summary": "Rack aware clusters now support disaggregated SAN deployments, …", "preview": true }
      ],
      "solutionUpdate": { "uri": "https://...", "fileHash": "..." },
      "urls": { "security": "https://...", "news": "https://...", "issues": "https://..." }
    }
  ]
}
```

`supported` reflects the time of generation. Consumers that need an accurate value should compare `endOfSupportDate` to the current date.

### Calendar (ICS)

`calendar.ics` has one all-day event per release on its end of support date (all releases, including ones that already ended). Subscribe to it by URL rather than importing the file, so your calendar picks up new releases automatically:

- **Outlook**: *Add calendar → Subscribe from web*, paste `https://lifecycle.azl.graa.dev/calendar.ics`
- **Google Calendar**: *Other calendars → From URL*
- **Apple Calendar**: *File → New Calendar Subscription*, or open `webcal://lifecycle.azl.graa.dev/calendar.ics`

`calendar-reminders.ics` is the same calendar with a reminder at 09:00, 30 and 7 days before each end of support. Pick the one that fits: Outlook and Apple Calendar honor these reminders, Google Calendar ignores reminders in subscribed calendars. Use one of the two, not both.

Technical notes: valid RFC 5545 (CRLF line endings, folded lines, escaped text), events are transparent (they do not mark you busy) and carry a stable `UID` such as `azure-local-12.2610-eos@releases.azurelocal.graa.dev` (major version and release train, so a later build superseding the release, or a changed site domain, updates the event instead of duplicating it; the identifier deliberately keeps the original domain `releases.azurelocal.graa.dev` even though the site now lives at `lifecycle.azl.graa.dev`, because changing a UID would make existing subscribers see every event twice). Events are named after the train, `Azure Local 12.2610 end of support`, and the description lists the latest build. The calendar suggests a daily refresh (`REFRESH-INTERVAL`); clients decide how often they poll.

### Feature highlights

`features` lists up to five highlights per release, taken from the matching *Features and improvements in 2610* (and so on for each release train) section of Microsoft's [What's new](https://learn.microsoft.com/en-us/azure/azure-local/whats-new) article (the full notes are linked from `urls.news`). It is best effort:

- Each entry has a `title`, a short `summary` (link sentences removed, truncated at 220 characters) and a `preview` flag for features marked as preview.
- Boilerplate entries that appear in nearly every release (OS changes, .NET and PowerShell updates, Azure Migrate, documentation updates) are skipped.
- All releases in the same train share the same highlights, for example 11.2510 and 12.2510.
- `features` is an empty array for releases without highlights, such as older trains the article no longer covers or releases that only contain boilerplate. The site then links to the release notes instead.
- If the article can't be parsed during a run, highlights already published are kept rather than dropped.
- The three first highlights are also added to the description of each RSS and JSON Feed item.

### How end of support is determined

Microsoft states that each Azure Local release is supported for six months. `endOfSupportDate` is `firstAvailabilityDate` + 180 days, where `firstAvailabilityDate` is when the first build of the release became available. The documentation lists later builds of a release as superseding earlier ones (`supersedes`), and `availabilityDate` is the date of the latest build. The site flags releases ending within 60 days as *ending soon*.

## 🧰 PowerShell cmdlet

The cmdlet `Get-AzureLocalRelease` retrieves Azure Local releases from Microsoft's documentation and is what generates the data above.

[![Cmdlet](/assets/cmdlet.png)](https://github.com/erikgraa/azure-local-releases/tree/main/scripts/Get-AzureLocalRelease.ps1)

```powershell
git clone https://github.com/erikgraa/azure-local-releases.git
. .\azure-local-releases\scripts\Get-AzureLocalRelease.ps1

Get-AzureLocalRelease
Get-AzureLocalRelease -SupportedReleases
```

Parameters: `-Uri` (documentation URL), `-SupportedReleases` (only releases not yet at end of support), `-OutputType String|Version` (type of `version`) and `-SkipFeatures` (don't retrieve feature highlights from the What's new article).

What changed in the cmdlet:

- Parses the current layout of Microsoft's release information, including the "Older versions" tables for 26100.xxx (12.x), 25398.xxx (11.x) and 25398.xxx (10.x), instead of relying on tab ids and a column layout that no longer exist.
- Follows the chain of builds in a table row (`Supersedes: <version> Availability date: <date>`). `version` and `availabilityDate` are the latest build, `firstAvailabilityDate` is when the release first became available and `supersedes` lists the earlier builds.
- Reads which build is meant for new deployments (`newDeployments`) from the "New deployments of this software use the … build" note.
- Adds `firstAvailabilityDate`, `osVersion` (`24H2`/`23H2`), `supersedes` and `features`. Existing properties are kept, and `supported` now compares dates correctly.
- Retrieves feature highlights per release train from the What's new article, see [Feature highlights](#feature-highlights).
- Falls back to the general documentation pages when a row has no links, ignores the offline update ZIP lookup if it is unavailable (with a warning) and throws if no releases are found, so a documentation change is noticed rather than producing empty data.

## 🛠 Development

The site is plain HTML, CSS and JavaScript in [site](site) with no build step and no external dependencies or fonts (all paths are relative, so it works under a Pages project path). Generate the data and preview it locally (requires PowerShell 7):

```powershell
./scripts/Build-Site.ps1

cd site
python -m http.server 8000   # or any other static file server
```

`Build-Site.ps1` writes `site/data/releases.json`, `site/feed.xml`, `site/feed.json`, `site/calendar.ics`, `site/calendar-reminders.ics` and `json/azure-local-releases.json`. These files are committed: the existing `site/data/releases.json` is the baseline the next run is compared against, see [Deployment](#deployment).

```powershell
./scripts/Build-Site.ps1          # writes files only if the content changed
./scripts/Build-Site.ps1 -Force   # always write, for instance after changing the site URL

./scripts/Test-SiteOutput.ps1     # validate the generated files in site/ and json/
Invoke-Pester ./tests             # offline tests (Pester 5), also run by the workflow
```

### Deployment

The workflow [`.github/workflows/pages.yml`](.github/workflows/pages.yml) ("Build and deploy site") keeps the site and data up to date.

| Trigger | When | Deploys |
| --- | --- | --- |
| Schedule | Daily at 06:00 UTC (`cron: "0 6 * * *"`) | Only if the data changed |
| Push to `main` | When `scripts/**`, `site/**`, `tests/**` or the workflow itself changes | Always, so site changes go live |
| Manual | *Run workflow* on the Actions tab (`workflow_dispatch`), optionally with *force* | Always |

What it does:

1. **build** job: runs the Pester tests, then `scripts/Build-Site.ps1` with PowerShell 7. The script fetches Microsoft's release information and What's new article, generates every output in a temporary directory, validates it (see [Failure protection](#failure-protection-and-alerts)) and compares the result with the committed `site/data/releases.json`, **ignoring the `generatedAt` timestamp**. If the content is identical it writes nothing and reports `changed=false`.
2. If the content changed, the files are replaced atomically (JSON data, RSS feed, JSON Feed, both calendars and `json/azure-local-releases.json`, with a new `generatedAt`) and the workflow commits them to `main` as `github-actions[bot]` (commit message "Auto updating Azure Local Releases"). Commits made with the workflow token do not retrigger the workflow.
3. Validates the files once more with `scripts/Test-SiteOutput.ps1` and checks the data freshness, then uploads `site/` as a Pages artifact, unless this is a scheduled run where nothing changed.
4. **deploy** job (only on `main`): publishes the artifact with `actions/deploy-pages`. It is skipped on scheduled runs where nothing changed, unless a `parser-broken` issue is open (so a deployment that failed earlier is retried).
5. **notify** job: opens, updates or closes the alert issues, see [Alerts](#alerts).

So on a day where Microsoft's documentation has not changed, a scheduled run fetches, compares and stops: **no commit and no redeploy**. Data changes that count include a new release, new feature highlights, a release reaching its end of support date (`supported` flips) and a different recommended build. The status and days left are calculated in the browser, so they stay correct between refreshes even without a redeploy.

If `main` has branch protection that blocks pushes from `github-actions[bot]`, allow the bot to bypass it or the data commit step will fail.

Permissions are scoped per job: `contents: write` (to commit the data), `pages: write` (for `actions/configure-pages`) and `issues: read` (to see open alerts) for the build job, `pages: write` plus `id-token: write` for the deploy job, which uses the `github-pages` environment, and `issues: write` for the notify job. The artifact is `site/`, including `site/CNAME`. No extra secrets are used.

### Failure protection and alerts

#### Failure protection

A parser or script failure must never publish empty or degraded files. `Build-Site.ps1` builds all outputs in a temporary directory and runs `scripts/Test-SiteOutput.ps1` on them before any real file is touched; only if that passes are the files replaced, one by one, each atomically (written next to the target and renamed over it). Any problem makes the step fail with the reason listed: the committed data, feeds and calendars stay as they were, nothing is committed and nothing is deployed, so the last good site stays live. The checks cover all outputs (JSON data, RSS, JSON Feed, both ICS calendars and the plain JSON array):

- at least 20 releases, at least one supported release and a recommended build for new deployments
- required fields present (version, dates, OS build, release train, links), version format, unique versions
- sane dates: valid `yyyy-MM-dd`, not in the future, first availability not after the latest build, end of support exactly 180 days after first availability
- not more than 10% fewer releases than the committed data, and the newest release not older than the newest committed one
- RSS and JSON Feed are well formed, non-empty, list the same items and contain the newest release
- both calendars are structurally valid RFC 5545, have one event per release with the end of support date as start, unique UIDs, the same events in both, and reminders only in the reminders calendar

The tests in [tests](tests) (`Invoke-Pester ./tests`, run by the workflow before every build) cover the happy path, ICS output and UID stability, and failure cases (empty or too small result, big drop, missing fields, bad dates, nothing supported, garbage input) asserting that every existing file is byte-for-byte unchanged afterwards. The workflow also validates the working tree once more right before committing and uploading, including runs where nothing changed.

#### Alerts

The `notify` job uses only the built-in `GITHUB_TOKEN`:

- **Run failed** (parsing, validation, tests, commit or deployment): opens an issue labelled `parser-broken` with a link to the failed run and the validation error. If one is already open, a comment with the new run is added instead (once per run, so the issue never gets duplicates). The issue is **closed automatically** with a comment when a later run succeeds. While it is open, scheduled runs redeploy even if the data did not change.
- **Data looks stale**: the data changes at least monthly (a new release, or a release reaching end of support), so if `generatedAt` in `data/releases.json` is older than 60 days an issue labelled `data-stale` is opened (the build still succeeds). This catches a parser that runs fine but no longer finds anything new. It closes automatically once the data is refreshed. Change the limit with the repository variable `STALE_AFTER_DAYS`.
- The labels are created on first use. Watch the repository (or just the issues) to get the alert by email or in the GitHub notifications.
- **Email**: GitHub also emails the owner about **failed scheduled workflow runs** by default (to the person who last changed the cron schedule in the workflow file), as long as notifications for Actions are enabled in *Settings → Notifications → Actions*. That email works even if the issue alert itself fails.
- Scheduled workflows in a public repository are disabled by GitHub after 60 days without repository activity. The daily run commits data changes, but if you see a "workflow disabled" notice, re-enable it on the Actions tab. If nothing runs, nothing alerts; the stale check is only evaluated when the workflow runs.

### One-time setup

The repository is already set up for Pages with GitHub Actions as the source and the custom domain `lifecycle.azl.graa.dev`. In a fork, or if you change the domain:

1. **Source**: **Settings → Pages → Build and deployment → Source** must be **GitHub Actions**. Without this the deploy job cannot publish.
2. **Custom domain**: set it under **Settings → Pages → Custom domain** and keep [`site/CNAME`](site/CNAME) in sync. The file is part of the published artifact, and `Build-Site.ps1` uses it as the base URL for the absolute links in the feeds (override with the repository variable `SITE_URL` or `-SiteUrl`). Changing the domain regenerates the feeds on the next run. Without a custom domain, delete `site/CNAME` and the site is served from `https://<owner>.github.io/<repo>/`, which works too because all site links are relative.
3. **DNS**: the domain needs a `CNAME` record pointing to `<owner>.github.io` (for `lifecycle.azl.graa.dev`: `erikgraa.github.io`). If it still points at the old Azure Container App, change it. It can take a while before GitHub provisions the certificate.
4. **HTTPS**: once the certificate is ready, tick **Enforce HTTPS** under Pages.
5. Run the workflow once from the Actions tab (or push to `main`) to publish the first version.

## 🗑 What was removed

| Removed | Why / replacement |
| --- | --- |
| `pode/` (Pode server, views, OpenAPI/Swagger) | Replaced by the static site in `site/` |
| `Dockerfile` | No container is needed any more |
| `.github/workflows/containerapp.yml` (Docker Hub, ACR and Azure Container App deploy) | Replaced by `pages.yml`. The Azure Container App, its registry and the related repository secrets (`DOCKERHUB_*`, `AZURE_CREDENTIALS`, `REGISTRY_*`, `CONTAINER_APP_NAME`, `RESOURCE_GROUP`) and variable `CONTAINER_IMAGE_NAME` are no longer used and can be deleted |
| `.github/workflows/json.yml` | Merged into `pages.yml`, which also keeps `json/azure-local-releases.json` updated |
| `assets/pode.png` | No longer relevant |
| Query API `/api/releases` (`supported`, `releaseTrain`, `baselineRelease`, `osBuild`, `version`, `newDeployments`, `solutionUpdate`, `latest`) and `/api/releasetrains` | A static site cannot filter server side. Fetch `data/releases.json` and filter client side, for example `jq '.releases[] \| select(.supported)'` or `Where-Object supported`. `trains` in the JSON replaces `/api/releasetrains` and `newDeployments` replaces `?newDeployments=true`. |

The previous demo at `releases.azurelocal.graa.dev` was hosted by the container app. The site now lives at `lifecycle.azl.graa.dev` on GitHub Pages, so the DNS record for the new domain has to point at GitHub Pages, see [One-time setup](#one-time-setup).

## ✍ Blog post

See the related blog posts at https://blog.graa.dev for possible use cases:
* https://blog.graa.dev/AzureLocal-Releases
* https://blog.graa.dev/AzureLocal-LimitedConnectivity

## 🌳 Repository

```plaintext
│   LICENSE
│   README.md
│
├───.github
│   └───workflows
│           pages.yml
│
├───assets
│       cmdlet.png
│       demo.png
│
├───json
│       azure-local-releases.json
│
├───scripts
│       Build-Site.ps1
│       Get-AzureLocalRelease.ps1
│       Test-SiteOutput.ps1
│
├───tests
│       Build-Site.Tests.ps1
│
└───site
    │   apple-touch-icon.png
    │   app.js
    │   calendar-reminders.ics
    │   calendar.ics
    │   CNAME
    │   favicon-32.png
    │   favicon.svg
    │   feed.json
    │   feed.xml
    │   icon-192.png
    │   icon-512.png
    │   index.html
    │   og-image.png
    │   site.webmanifest
    │   style.css
    │   sw.js
    │
    └───data
            releases.json
```

## 👏 Contributions

Any contributions are welcome and appreciated! Issues and pull requests are welcome.

## ⚖️ Disclaimer

This is an independent, community-driven project. It is not affiliated with, endorsed by, or sponsored by Microsoft, and Azure and Azure Local are trademarks of Microsoft Corporation. Dates are derived from [Microsoft's public release documentation](https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2), so verify them against the official docs and your OEM vendor's guidance before planning upgrades.
