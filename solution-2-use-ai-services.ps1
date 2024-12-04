<#
**********************************************************
Create and consume Azure AI Services
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
# to see all kind of Cognitive services: az cognitiveservices account list-kinds
az cognitiveservices account create -n $AISERVICESNAME -g $RESOURCEGROUP --kind CognitiveServices --sku S0 -l $LOCATION --yes

git clone https://github.com/MicrosoftLearning/mslearn-ai-services
# Follow the exercise instructions.

#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

