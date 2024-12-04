<#
**********************************************************
Get Started with Azure AI Services
**********************************************************
#>

Exercise: https://microsoftlearning.github.io/mslearn-ai-services/Instructions/Exercises/01-use-azure-ai-services.html

# CONFIG
$RESOURCEGROUP="learn-ai-rg"
$LOCATION="northeurope"
$AISERVICESNAME="ld-learn-ai-service"

#**********************************************************
# Exercise - Use Azure AI services

az group create --name $RESOURCEGROUP --location $LOCATION

## create Azure AI Services resource as in exercise described  (canot be created though CLI)

#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

