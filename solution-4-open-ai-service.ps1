<#
**********************************************************
Get started with Azure OpenAI Service 
**********************************************************
#>

# CONFIG
$RESOURCEGROUP="ld-learn-ai-rg"
$LOCATION="uksouth" # openai is not available for northeurope or westeurope.
$OPENAISERVICESNAME="ld-learn-openai-service"
$MODELNAME="gpt-35-turbo-16k"
$MODELVERSION="0613"

#**********************************************************
# Exercise - Use Azure AI services

az group create --name $RESOURCEGROUP --location $LOCATION

# to see all kind of Cognitive services: az cognitiveservices account list-kinds
az cognitiveservices account create -n $OPENAISERVICESNAME -g $RESOURCEGROUP --kind OpenAI  --sku s0 -l $LOCATION
 
# deploy model
az cognitiveservices account deployment create  -g $RESOURCEGROUP -n $OPENAISERVICESNAME --deployment-name "my-$MODELNAME-deployment" --model-name $MODELNAME --model-version $MODELVERSION --model-format OpenAI --sku-name "Standard" --sku-capacity 1

Go to: https://ai.azure.com/

#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts: 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}