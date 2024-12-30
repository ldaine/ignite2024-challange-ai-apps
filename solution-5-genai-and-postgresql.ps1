<#
**********************************************************
Get started with generative AI in Azure Database for PostgreSQL 
**********************************************************
#>

# CONFIG
$LOCATION="uksouth" # openai is not available for northeurope or westeurope.
$RESOURCEGROUP="ld-learn-postgresql-ai-rg-$LOCATION"
$PG_ADMIN_USERNAME="pgAdmin"
$PG_ADMIN_PASSWORD="eS9soB8BYJlMQuln"
$TEMPLATE_LOCATION = ".\my-mslearn-postgresql\Allfiles\Labs\Shared\deploy.bicep"

#**********************************************************
# Exercise-Explore the Azure AI extension

Exercise: https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/12-explore-azure-ai-extension.html

az group create --name $RESOURCEGROUP --location $LOCATION

$CREATED_RESOURCES = az deployment group create --resource-group $RESOURCEGROUP --template-file $TEMPLATE_LOCATION --parameters restore=false adminLogin=pgAdmin adminLoginPassword=$PG_ADMIN_PASSWORD
# convert to object for easy use
$CREATED_RESOURCES_CONVERTED = ConvertFrom-Json -InputObject "$CREATED_RESOURCES"

#-----------------------------------------------------------------------
# Connecting and setting up Postgre database
#-----------------------------------------------------------------------

# Download PostgeSQL installer from https://www.postgresql.org/download/
# Run the intaller and schoose to install 'Command Line Tools'. Finish installation. 

# Open new PS window
# Go to PostgreSQL bin folder. (the path is set during installation)
cd 'C:\Program Files\PostgreSQL\17\bin'

$PG_SERVER_NAME = "psql-learn-$LOCATION-kr2shcyizikyg"
$PG_SERVER_HOST = az postgres flexible-server show --resource-group $RESOURCEGROUP --name $PG_SERVER_NAME  --query fullyQualifiedDomainName  --output tsv
$DB_NAME = "rentals"

# Connect to to Postge SQL DB
./psql.exe --host=$PG_SERVER_HOST  --port=5432 --username=$PG_ADMIN_USERNAME --dbname=$DB_NAME --set=sslmode=require


# you must provide full path to the CSV files
# <my-repo-path>  is the full path of the repo folder 
\COPY listings FROM <my-repo-path>/my-mslearn-postgresql/Allfiles/Labs/Shared/listings.csv CSV HEADER;
\COPY reviews FROM <my-repo-path>/my-mslearn-postgresql/Allfiles/Labs/Shared/reviews.csv CSV HEADER;

#-----------------------------------------------------------------------
# Adding Postgre Azure AI Extensions
#-----------------------------------------------------------------------

# AI Extension
SHOW azure.extensions;
# azure_ai and vector must be in the extension list

# exit psql

# get your subscriptions 
$SUBSCRIPTIONS = az account subscription list
$SUBSCRIPTIONS_CONVERTED = ConvertFrom-JSON -InputObject "$SUBSCRIPTIONS"
# if you have only one subsription
$YOUR_SUBSCRIPTION = $SUBSCRIPTIONS_CONVERTED[0].subscriptionId

# connect to to Postge SQL DB
# allow extensions in postgres DB 
az postgres flexible-server parameter set --resource-group $RESOURCEGROUP  --server-name $PG_SERVER_NAME --subscription $YOUR_SUBSCRIPTION --name azure.extensions --value azure_ai,vector

# go back to psql 
CREATE EXTENSION IF NOT EXISTS azure_ai;
\x auto

# viw objects in azure_ai extension 
\dx+ azure_ai
\df azure_ai.*

#-----------------------------------------------------------------------
# working with azure_ai extension
#-----------------------------------------------------------------------

# link azure_ai extension with azure ai service 

#get openai resource keys 
$OPENAI_SERVICE_ENDPOINT = $CREATED_RESOURCES_CONVERTED.properties.outputs.azureOpenAIEndpoint.value
$OPENAI_SERVICE_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.azureOpenAIServiceName.value
$KEYS =az cognitiveservices account keys list --resource-group $RESOURCEGROUP --name  $OPENAI_SERVICE_NAME
$KEYS_CONVERTED = ConvertFrom-JSON -InputObject "$KEYS"

# Set settings in psql
$OPENAI_SERVICE_ENDPOINT | Clip
# paste as {endpoint}
SELECT azure_ai.set_setting('azure_openai.endpoint', '{endpoint}');

$KEYS_CONVERTED.key1 | Clip
# paste as {api-key}
SELECT azure_ai.set_setting('azure_openai.subscription_key', '{api-key}');

# check if it was set correctly 
SELECT azure_ai.get_setting('azure_openai.endpoint');
SELECT azure_ai.get_setting('azure_openai.subscription_key');

# to test open ai extensions: 

<#
 SELECT
     id,
     name,
     azure_openai.create_embeddings('embedding', description) AS vector
 FROM listings
 LIMIT 1;
#>
# the genarated vector is large, so the result might not fit in command line.

#----------------------------------------------------------------------
# working with azure_cognitive extension
#-----------------------------------------------------------------------

# link azure_cognitive extension with azure cognitive service 
# Set settings in psql
$COGNITIVE_SERVICE_ENDPOINT = $CREATED_RESOURCES_CONVERTED.properties.outputs.languageServiceEndpoint.value
$COGNITIVE_SERVICE_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.languageServiceName.value
$COGNITIVE_KEYS =az cognitiveservices account keys list --resource-group $RESOURCEGROUP --name  $COGNITIVE_SERVICE_NAME
$COGNITIVE_KEYS_CONVERTED = ConvertFrom-JSON -InputObject "$COGNITIVE_KEYS"
$COGNITIVE_SERVICE_ENDPOINT | Clip
# paste as {endpoint}
SELECT azure_ai.set_setting('azure_cognitive.endpoint', '{endpoint}');

$COGNITIVE_KEYS_CONVERTED.key1 | Clip
# paste as {api-key}
SELECT azure_ai.set_setting('azure_cognitive.subscription_key', '{api-key}');

# check if it was set correctly 
SELECT azure_ai.get_setting('azure_cognitive.endpoint');
SELECT azure_ai.get_setting('azure_cognitive.subscription_key');

# to test cognitive extension: 

<#
 SELECT
     id,
     comments,
     azure_cognitive.analyze_sentiment(comments, 'en') AS sentiment
 FROM reviews
 WHERE id IN (3);
#>

#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}

