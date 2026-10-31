# Azure Local Releases

A static site that shows [Azure Local](https://learn.microsoft.com/en-us/azure/azure-local/) releases, when they became available, whether they are still supported and when they reach end of support. It is rebuilt daily from [Microsoft's release information](https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2) and hosted on GitHub Pages.

[![Build and deploy site](https://github.com/erikgraa/azure-local-releases/actions/workflows/pages.yml/badge.svg)](https://github.com/erikgraa/azure-local-releases/actions/workflows/pages.yml)

> [!IMPORTANT]  
> This tool only covers generic Azure Local releases as parsed from [Microsoft's documentation](https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2). Please verify with specific OEM hardware vendors' documentation for supported installation/upgrade paths according to their particular compatibility matrices

## 🎬 Site

Live at https://erikgraa.github.io/azure-local-releases/.

[![Azure Local releases site](/assets/demo.png)](https://erikgraa.github.io/azure-local-releases/)

- Status badges (**Supported**, **Ending soon**, **End of support**) and countdowns to end of support
- Search, filter by status and OS version (24H2/23H2) and sortable columns; the view is kept in the URL so it can be shared
- Links to what's new, security updates, known issues and solution update ZIPs
- Light and dark mode

## 📡 Feeds and data

| Artifact | URL |
| --- | --- |
| RSS 2.0 feed of new releases | https://erikgraa.github.io/azure-local-releases/feed.xml |
| JSON Feed 1.1 of new releases | https://erikgraa.github.io/azure-local-releases/feed.json |
| Releases and release trains as JSON | https://erikgraa.github.io/azure-local-releases/data/releases.json |
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
      "solutionUpdate": { "uri": "https://...", "fileHash": "..." },
      "urls": { "security": "https://...", "news": "https://...", "issues": "https://..." }
    }
  ]
}
```

`supported` reflects the time of generation. Consumers that need an accurate value should compare `endOfSupportDate` to the current date.

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

## 🛠 Development

The site is plain HTML, CSS and JavaScript in [site](site) with no build step. Generate the data and preview it locally (requires PowerShell 7):

```powershell
./scripts/Build-Site.ps1

cd site
python -m http.server 8000   # or any other static file server
```

`Build-Site.ps1` writes `site/data/releases.json`, `site/feed.xml` and `site/feed.json` (git-ignored, generated on deploy) and refreshes `json/azure-local-releases.json`. It fails instead of producing a site if too few releases are parsed, so a change in Microsoft's documentation format never publishes an empty site.

### Deployment

The [workflow](.github/workflows/pages.yml) runs on pushes to `main`, daily and on demand. It generates the data, commits `json/azure-local-releases.json` if it changed and deploys `site` to GitHub Pages.

To enable it in a fork, set **Settings → Pages → Build and deployment → Source** to **GitHub Actions**. If the site is served from a custom domain, set the repository variable `SITE_URL` so the feeds contain the right links.

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
        index.html
        style.css
```

> [!NOTE]
> The earlier Pode API and container app deployment have been replaced by the static site. The JSON files above replace the former `/api/releases` endpoints; filter them client-side (for example with `jq` or `Where-Object`).

## 👏 Contributions

Any contributions are welcome and appreciated!
