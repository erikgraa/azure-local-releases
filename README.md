# API for Azure Local Releases with Pode

The artifacts in this repository help increasing observability of Azure Local releases by offering them as PowerShell objects or as JSON through an API running [Pode](https://badgerati.github.io/Pode).

## 🎬 Example

See a demo of the Azure Local Releases Pode API at https://azlocalreleases.graa.dev, hosted as an Azure Container App.

[![GitHub Build and Deploy](https://github.com/erikgraa/azure-local-releases/actions/workflows/containerapp.yml/badge.svg)](https://github.com/erikgraa/azure-local-releases/actions/workflows/containerapp.yml)

## 🚀 Artifacts

### PowerShell cmdlet 

The PowerShell cmdlet `Get-AzureLocalRelease` retrieves Azure Local releases from Microsoft's documentation.

[![Cmdlet](/assets/cmdlet.png)](https://github.com/erikgraa/azure-local-releases/tree/main/scripts/Get-AzureLocalRelease.ps1)

### Pode API

The Pode API solution uses the cmdlet `Get-AzureLocalRelease` to provide information about Azure Local releases.

[![Pode](/assets/pode.png)](https://azlocalreleases.graa.dev)

## 📄 Usage

### PowerShell cmdlet 

The PowerShell cmdlet can run locally and the objects converted to JSON.

```powershell
git clone https://github.com/erikgraa/azure-local-releases.git
. .\azure-local-releases\scripts\Get-AzureLocalRelease.ps1

$releases = Get-AzureLocalRelease

$releases | ConvertTo-Json
```

### Pode API

Pode can run locally or as a container workload.

### 1️⃣ Pode API locally

Run the Pode API standalone/locally like so:

```powershell
git clone https://github.com/erikgraa/azure-local-releases.git

cd azure-local-releases\pode
.\server.ps1
```

### 2️⃣ Pode API as a container workload

Build the container image and run it yourself:

```powershell
git clone https://github.com/erikgraa/azure-local-releases.git
cd azure-local-releases

docker build -t pode/azure-local-releases .
docker run --name pode -p 8080:8080 -d pode/azure-local-releases
```

## ✍ Blog post

See the related blog post at https://blog.graa.dev/AzureLocal-Releases for use cases.

## 🌳 Repository

The repository structure is as follows:

```plaintext
│   Dockerfile
│   LICENSE
│   README.md
│
├───.github
│   └───workflows
│           containerapp.yml
│           json.yml
│
├───assets
│       cmdlet.png
│       pode.png
│
├───json
│       azure-local-releases.json
│
├───pode
│   │   package.json
│   │   server.ps1
│   │   server.psd1
│   │
│   └───views
│           index.pode
│
└───scripts
        Get-AzureLocalRelease.ps1
```

## 👏 Contributions

Any contributions are welcome and appreciated!