# reference https://chocolatey.org/packages for all available packages
$Applications = @(
	"vscode"
)

# Install/Update Chocolatey
function installChocolatey {
	Write-Output "Checking to see if Chocolatey is installed..."

	if (Get-Command choco -errorAction SilentlyContinue) {
		Write-Output "Chocolatey is already installed"
		choco.exe upgrade chocolatey -y
		
		Write-Output "Attempting to update apps using chocolatey"
		choco.exe upgrade $Applications -y
	}
	else {
		Write-Output "Chocolatey isn't installed, attempting to install. "
		Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

		Write-Output "Attempting to install apps with chocolatey"
		choco install $Applications -y
	}
}

function installwsl {
	Write-Output "installing windows subsystem for linux"
	wsl --update
	wsl --install
	wsl sudo apt-get update
	wsl sudo apt-get upgrade
	wsl sudo apt-get install just
}

installChocolatey
installwsl