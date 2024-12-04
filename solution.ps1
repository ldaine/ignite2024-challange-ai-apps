<#
**********************************************************
 Orchestrate containers for cloud-native apps with AKS
**********************************************************
#>

# CONFIG
$REGISTRYNAME="ldcnaconreg"
$CLUSTERNAME="cna-demo-aks"
$RESOURCEGROUP="learn-cna-rg"
$LOCATION="northeurope"
$ZONENAME="ligadaine.pro"
$WEBAPPNAME="ld-cna-demo-webapp"

#**********************************************************
# Exercise - Create an AKS cluster

az group create --name $RESOURCEGROUP --location $LOCATION
az acr create --resource-group $RESOURCEGROUP --name $REGISTRYNAME --admin-enabled true --sku Standard --location $LOCATION

# The repo is already cloned in this repo
# if you want to clone the original repo: 
# git clone https://github.com/MicrosoftDocs/mslearn-cloud-native-apps-express.git
# cd my-mslearn-cloud-native-apps-express/src
cd my-mslearn-cloud-native-apps-express/src
az acr build --registry $REGISTRYNAME --image expressimage .
cd ..

# create aks (with app-routing enabled)
az aks create --resource-group $RESOURCEGROUP --name $CLUSTERNAME  --attach-acr $REGISTRYNAME  --location $LOCATION  --enable-app-routing  --generate-ssh-keys  --node-count 2

cd react
az acr build --registry $REGISTRYNAME --image webimage .
cd ..

#**********************************************************
# Exercise - Set up a development environment with AKS

# Configure kubecl
# Connect to your AKS cluster
az aks get-credentials --resource-group $RESOURCEGROUP --name $CLUSTERNAME
kubectl get nodes

# Deploy your container to AKS
cd aks
$ACR_LOGIN_SERVER = az acr list --resource-group $RESOURCEGROUP --query "[].{acrLoginServer:loginServer}" --output tsv # works only if there is one value
(Get-Content -path ./deployment.yaml) -replace '<AcrLoginServer>', $ACR_LOGIN_SERVER | Set-Content -Path ./deployment.yaml
# ldcnaconreg.azurecr.io = return value of 'az acr list ..'
# Bash: sed -i -e 's/<AcrLoginServer>/ldcnaconreg.azurecr.io/g' deployment.yaml # or edit with 'code .'
kubectl apply -f ./deployment.yaml
kubectl get deploy cna-express
kubectl get pods

kubectl apply -f ./service.yaml
kubectl get service cna-express

#**********************************************************
# Exercise - Connect cloud-native components

# Create the Ingress object
# https://learn.microsoft.com/en-us/azure/aks/app-routing#create-the-ingress-object

# update ingress.yaml (if needed)
code .
<#
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cna-express
spec:
  ingressClassName: webapprouting.kubernetes.azure.com
  rules:
  - http:
      paths:
      - path: / # Which path is this rule referring to
        pathType: Prefix
        backend: # How the ingress will handle the requests
          service:
            name: cna-express # Which service the request will be forwarded to
            port: 
              name: http # Which port in that service
#>
# Azure Portal CLI: ctrl+s, ctrl+q

kubectl apply -f ./ingress.yaml
kubectl get service --namespace app-routing-system nginx -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
kubectl get ingress cna-express
# you can test if the application is deployed by going to the returned IP

# Adding DNS Zone to be able to access the app with custom domain
# https://learn.microsoft.com/en-us/azure/aks/app-routing-dns-ssl#create-a-public-azure-dns-zone

az network dns zone create --resource-group $RESOURCEGROUP --name $ZONENAME
$ZONEID=az network dns zone show --resource-group $RESOURCEGROUP --name $ZONENAME --query "id" --output tsv
# bash alternative
# ZONEID=$(az network dns zone show --resource-group $RESOURCEGROUP --name $ZONENAME --query "id" --output tsv)
az aks approuting zone add --resource-group $RESOURCEGROUP --name $CLUSTERNAME --ids=${ZONEID} --attach-zones

# update nameservers in your domain name provider with NS values from recordsets
# check the configuration
nslookup -type=SOA $ZONENAME 

$TARGETHOSTNAME="cna-express.ligadaine.pro"

# update ingress.yaml with yout custom domain
code .
<#
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: cna-express
spec:
  ingressClassName: webapprouting.kubernetes.azure.com
  rules:
  - host: <$TARGETHOSTNAME>
    http:
      paths:
      - path: / # Which path is this rule referring to
        pathType: Prefix
        backend: # How the ingress will handle the requests
          service:
            name: cna-express # Which service the request will be forwarded to
            port: 
              name: http # Which port in that service
#>
# Azure Portal CLI: ctrl+s, ctrl+q

kubectl apply -f ./ingress.yaml
kubectl get ingress cna-express
# It takes a while to deploy the changes (although the command is exxecuted). The access to the application though host is available after couple of minutes. 

#***********************************************
# WEBAPPP

# get container registry name
$ACR_LOGIN_SERVER = az acr list --resource-group $RESOURCEGROUP --query "[].{acrLoginServer:loginServer}" --output tsv # works only if there is one value

# get all your plans 
az appservice plan list
$LINUX_F1_PLAN_NAME = "daine-it-homepage-linux-plan"
# get credentials
$CREDENTIALS = az acr credential show -n $REGISTRYNAME | ConvertFrom-Json
$REGISTRYUSERNAME = $CREDENTIALS.username
$REGISTRYPASSWORD =  $CREDENTIALS.passwords[0].value
# username and password is needed to be able to pull the image
az webapp create --name $WEBAPPNAME --plan $LINUX_F1_PLAN_NAME --resource-group $RESOURCEGROUP --container-image-name $ACR_LOGIN_SERVER/webimage:latest --container-registry-user $REGISTRYUSERNAME --container-registry-password $REGISTRYPASSWORD
az webapp config appsettings set --name $WEBAPPNAME --resource-group $RESOURCEGROUP --settings SOCKET_SERVER_URL=$TARGETHOSTNAME

echo http://$WEBAPPNAME.azurewebsites.net
#open the generate url

# CLEANUP
# webapp only 'az webapp delete --name $WEBAPPNAME --resource-group $RESOURCEGROUP'

az group delete --name $RESOURCEGROUP -y
