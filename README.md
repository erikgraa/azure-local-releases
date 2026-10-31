# Azure Local Releases

A static site that shows [Azure Local](https://learn.microsoft.com/en-us/azure/azure-local/) releases, when they became available, whether they are still supported and when they reach end of support. It is rebuilt daily from [Microsoft's release information](https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2) and hosted on GitHub Pages.

[![Build and deploy site](https://github.com/erikgraa/azure-local-releases/actions/workflows/pages.yml/badge.svg)](https://github.com/erikgraa/azure-local-releases/actions/workflows/pages.yml)

> [!IMPORTANT]  
> This tool only covers generic Azure Local releases as parsed from [Microsoft's documentation](https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2). Please verify with specific OEM hardware vendors' documentation for supported installation/upgrade paths according to their particular compatibility matrices

## ✨ What's new

This repository used to offer a PowerShell cmdlet and a [Pode](https://badgerati.github.io/Pode) API hosted as an Azure Container App. It is now a static site on GitHub Pages:

- **Static releases site ("Release Radar")** with a hero showing the recommended release and a live countdown to the next end of support, a lifecycle timeline, a "Which version are you running?" checker and filterable release cards, all driven by the generated JSON data.
- **Feeds**: an RSS feed, a JSON Feed and a JSON data file (plus the plain JSON array that was already committed here).
- **Fixed cmdlet and parser**: `Get-AzureLocalRelease` had stopped working because Microsoft changed the layout of the release documentation (the committed JSON had not been updated since February 2026). The parser has been rewritten for the current layout and now also handles builds that supersede earlier ones.
- **End of support dates** derived from Microsoft's six-month support policy, see [How end of support is determined](#how-end-of-support-is-determined).
- **Daily automatic refresh** through a GitHub Actions workflow, see [Deployment](#deployment).
- **Removed**: the Pode app, the `Dockerfile`, the container app workflow and the query API, see [What was removed](#-what-was-removed).

## 🎬 Site

Live at https://releases.azurelocal.graa.dev/.

[![Azure Local releases site](/assets/demo.png)](https://releases.azurelocal.graa.dev/)

- **Hero**: the release recommended for new deployments (release date, end of support, OS build, link to the release notes) next to a live countdown (days, hours, minutes, seconds) to the next end of support and a retirement queue of all supported releases
- **Version checker**: pick the version you run and see how much runway you have, or that it is out of support, and what to update to
- **Lifecycle timeline**: a Gantt-style view with one bar per release train from first availability to end of support, the last 60 days hatched as *ending soon*, and a marker for today. Shows recent trains by default, with the full history one click away. Click a bar to jump to its releases.
- **Release cards**: status pill (**Recommended**, **Supported**, **Ending soon**, **End of support**), progress through the support window and days left. **Details** expands to the release's top feature highlights (with a *Preview* marker and a link to the full release notes), the OS build and earlier builds, links to what's new, security updates, known issues and the solution update ZIP, and buttons to copy the version or ZIP SHA256
- **Search, filters and sorting**: search by version, release train or OS build (press `/`), filter by status chip and OS version (24H2/23H2) and sort by newest, oldest or ends soonest. The view is kept in the URL so it can be shared.
- Feed links (RSS, JSON Feed, JSON data) in the header and footer
- Light and dark theme (follows your system, with a toggle), reduced-motion support and a layout for mobile screens
- Works offline once loaded: a small service worker caches the site and data (network first, so it never serves stale data when online). Status and countdowns are calculated in the browser, so they stay correct between daily data refreshes.

## 📡 Feeds and data

| Artifact | URL |
| --- | --- |
| RSS 2.0 feed of new releases | https://releases.azurelocal.graa.dev/feed.xml |
| JSON Feed 1.1 of new releases | https://releases.azurelocal.graa.dev/feed.json |
| Releases and release trains as JSON | https://releases.azurelocal.graa.dev/data/releases.json |
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

`Build-Site.ps1` writes `site/data/releases.json`, `site/feed.xml`, `site/feed.json` and `json/azure-local-releases.json`. These files are committed: the existing `site/data/releases.json` is the baseline the next run is compared against, see [Deployment](#deployment).

```powershell
./scripts/Build-Site.ps1          # writes files only if the content changed
./scripts/Build-Site.ps1 -Force   # always write, for instance after changing the site URL
```

### Deployment

The workflow [`.github/workflows/pages.yml`](.github/workflows/pages.yml) ("Build and deploy site") keeps the site and data up to date.

| Trigger | When | Deploys |
| --- | --- | --- |
| Schedule | Daily at 06:00 UTC (`cron: "0 6 * * *"`) | Only if the data changed |
| Push to `main` | When `scripts/**`, `site/**` or the workflow itself changes | Always, so site changes go live |
| Manual | *Run workflow* on the Actions tab (`workflow_dispatch`), optionally with *force* | Always |

What it does:

1. **build** job: runs `scripts/Build-Site.ps1` with PowerShell 7. The script fetches Microsoft's release information and What's new article and compares the result with the committed `site/data/releases.json`, **ignoring the `generatedAt` timestamp**. If the content is identical it writes nothing and reports `changed=false`.
2. If the content changed, the script writes the JSON data, RSS feed, JSON Feed and `json/azure-local-releases.json` (with a new `generatedAt`), and the workflow commits them to `main` as `github-actions[bot]` (commit message "Auto updating Azure Local Releases"). Commits made with the workflow token do not retrigger the workflow.
3. Uploads `site/` as a Pages artifact, unless this is a scheduled run where nothing changed.
4. **deploy** job (only on `main`): publishes the artifact with `actions/deploy-pages`. It is skipped on scheduled runs where nothing changed.

So on a day where Microsoft's documentation has not changed, a scheduled run fetches, compares and stops: **no commit and no redeploy**. Data changes that count include a new release, new feature highlights, a release reaching its end of support date (`supported` flips) and a different recommended build.

Guards: `Build-Site.ps1` throws, before any file is written, if fewer than 20 releases are parsed, no release is supported, the number of releases drops by more than 10% compared with the published data, or the newest release is older than the newest published one. The run then fails (the repository owner gets the usual failed workflow notification), the committed data stays as it was and the published site stays up. The countdowns and status badges are calculated in the browser, so they stay correct between refreshes even without a redeploy.

If `main` has branch protection that blocks pushes from `github-actions[bot]`, allow the bot to bypass it or the data commit step will fail.

Permissions are scoped per job: `contents: write` (to commit the data) and `pages: write` (for `actions/configure-pages`) for the build job, and `pages: write` plus `id-token: write` for the deploy job, which uses the `github-pages` environment. The artifact is `site/`, including `site/CNAME`.

### One-time setup

The repository is already set up for Pages with GitHub Actions as the source and the custom domain `releases.azurelocal.graa.dev`. In a fork, or if you change the domain:

1. **Source**: **Settings → Pages → Build and deployment → Source** must be **GitHub Actions**. Without this the deploy job cannot publish.
2. **Custom domain**: set it under **Settings → Pages → Custom domain** and keep [`site/CNAME`](site/CNAME) in sync. The file is part of the published artifact, and `Build-Site.ps1` uses it as the base URL for the absolute links in the feeds (override with the repository variable `SITE_URL` or `-SiteUrl`). Changing the domain regenerates the feeds on the next run. Without a custom domain, delete `site/CNAME` and the site is served from `https://<owner>.github.io/<repo>/`, which works too because all site links are relative.
3. **DNS**: the domain needs a `CNAME` record pointing to `<owner>.github.io` (for `releases.azurelocal.graa.dev`: `erikgraa.github.io`). If it still points at the old Azure Container App, change it. It can take a while before GitHub provisions the certificate.
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

The previous demo at `releases.azurelocal.graa.dev` was hosted by the container app. The same domain now serves the GitHub Pages site, so the DNS record has to point at GitHub Pages instead, see [One-time setup](#one-time-setup).

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
│
└───site
        app.js
        CNAME
        index.html
        style.css
        sw.js
```

## 👏 Contributions

Any contributions are welcome and appreciated!
