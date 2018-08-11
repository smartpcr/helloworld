# Environment Setup for Microservice Development Using AKS

For each developer, two environments are needed:

1. Windows 10 is used for daily development. 
2. Ubuntu is used for testing. 

## Dev Environment (Desktop, either Windows 10 or Mac)

### Setup Windows

- Minikube can be setup on windows via hyper-v or virtualbox, the script make sure minikube can be started reliably.
- Before doing anything, service principal needs to be setup, it's used by terraform to setup other resources. Since certificate format and storage is different between OS, we use different script used to setup service principal in Windows and Mac.

Run the following script step-by-step

``` powershell 
.\Scripts\Setup-DevBox.ps1
.\Scripts\Env\Setup-ServicePrincipal.ps1
```

### Setup Mac

Run the following script step-by-step 

``` bash
./Scripts/Setup-DevBox.sh
./Scripts/Env/Setup-ServicePrincipal.sh
```

## Ubuntu 18.0 LTS

1.	Create Ubuntu 18.04LTS from Azure.
2.	Install Desktop (Optional)
    ``` 
    sudo apt-get update
    sudo apt-get install xfce4
    ```
3.	Installed xrdp (Optional)
    ```
    sudo apt-get install xrdp
    echo xfce4-session >~/.xsession
    sudo service xrdp restart
    ```
4.	Chrome (optional)
 ```
 wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt-get update
sudo apt-get -y install google-chrome-stable
```
5.	SublimeText (Optional)
```
wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | sudo apt-key add -

echo "deb https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list
sudo apt-get update
sudo apt-get install sublime-text
```
6.	Install Docker
https://docs.docker.com/v17.09/engine/installation/linux/docker-ce/ubuntu/#set-up-the-repository

``` bash
sudo apt-get update
sudo apt-get install \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88

sudo add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

```

7.	Set sudo user for current session `sudo -s`

8.	Install Azure CLI
https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest

``` bash
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list

curl -L https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo apt-get install apt-transport-https
sudo apt-get update && sudo apt-get install azure-cli
```

test
``` bash
az login
```

9. Install virtualbox

``` bash
wget -q https://www.virtualbox.org/download/oracle_vbox_2016.asc -O- | sudo apt-key add -
wget -q https://www.virtualbox.org/download/oracle_vbox.asc -O- | sudo apt-key add -
sudo add-apt-repository "deb http://download.virtualbox.org/virtualbox/debian `lsb_release -cs` contrib"

sudo apt-get update
sudo apt-get install virtualbox-5.2
```

10.	Install kubectl

     `sudo snap install kubectl --classic`
``` bash
sudo apt-get update && sudo apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo touch /etc/apt/sources.list.d/kubernetes.list 
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubectl
```

11. Install minikube
``` bash
curl -Lo minikube https://storage.googleapis.com/minikube/releases/v0.28.2/minikube-linux-amd64 && chmod +x minikube && sudo mv minikube /usr/local/bin/
```

12.	Dockercompose 

    `sudo apt install docker-compose` 

11.	If you face error Remote error from secret service: org.freedesktop.DBus.Error.ServiceUnknown: The name org.freedesktop.secrets was not provided by any .service files
Error saving credentials: error storing credentials - err: exit status 1, out: `The name org.freedesktop.secrets was not provided by any .service files`
Follow  https://stackoverflow.com/questions/50151833/cannot-login-to-docker-account

13. Setup rdp user password
``` bash
sudo passwd azureuser # the user used to create vm
```

14. Start minikube

``` bash
# wait ~5 min first time (need to download and install kubelet, kubeadm)
minikube start

# if it hangs 

minikube delete
rm -rf ~/.minikube


```