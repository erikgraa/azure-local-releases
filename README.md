# Azure Local Releases Tool

The artifacts in this repository help increasing observability and traceability of Azure Local releases by offering details of them via a PowerShell cmdlet or through an API running [Pode](https://badgerati.github.io/Pode).  

[![GitHub Build and Deploy](https://github.com/erikgraa/azure-local-releases/actions/workflows/containerapp.yml/badge.svg)](https://github.com/erikgraa/azure-local-releases/actions/workflows/containerapp.yml)

## 🎬 Demo

See a live demo of the Azure Local Releases Pode API at https://releases.azurelocal.graa.dev (hosted as an Azure Container App).

[![Demo](/assets/demo.png)](https://releases.azurelocal.graa.dev)

## 🚀 Artifacts

### PowerShell cmdlet 

The PowerShell cmdlet `Get-AzureLocalRelease` retrieves Azure Local releases from Microsoft's documentation.

[![Cmdlet](/assets/cmdlet.png)](https://github.com/erikgraa/azure-local-releases/tree/main/scripts/Get-AzureLocalRelease.ps1)

### Pode API

Pode makes uses of the cmdlet `Get-AzureLocalRelease` to provide the details about Azure Local releases.

[![Pode](/assets/pode.png)](https://releases.azurelocal.graa.dev)

## 📄 Usage

### PowerShell cmdlet 

The PowerShell cmdlet `Get-AzureLocalRelease` can run locally.

```powershell
git clone https://github.com/erikgraa/azure-local-releases.git
. .\azure-local-releases\scripts\Get-AzureLocalRelease.ps1

Get-AzureLocalRelease
```

### Pode API

Pode can run locally or for instance as a container workload.

### 1️⃣ Run Pode API locally

Run the Pode API standalone/locally like so:

```powershell
Install-Module -Name Pode -MinimumVersion 2.12.0

git clone https://github.com/erikgraa/azure-local-releases.git

cd azure-local-releases\pode
.\server.ps1
```

### 2️⃣ Run Pode API as a container workload

Build the container image and run it yourself:

```powershell
git clone https://github.com/erikgraa/azure-local-releases.git
cd azure-local-releases

docker build -t pode/azure-local-releases .
docker run --name pode -p 8080:8080 -d pode/azure-local-releases
```

## ✍ Blog post

See the related blog post at https://blog.graa.dev/AzureLocal-Releases for possible use cases.

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