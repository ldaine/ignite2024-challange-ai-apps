<#
**********************************************************
Enable semantic search in Azure Database for PostgreSQL
**********************************************************
#>

#**********************************************************
# Exercise 1 - Generate vector embeddings with Azure OpenAI
# https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/13-generate-vector-embeddings-azure-openai.html

# CONFIG
# region must support abstractive summarization
# https://learn.microsoft.com/en-us/azure/ai-services/language-service/summarization/region-support
$LOCATION="uksouth"
$RESOURCEGROUP="ld-learn-postgresql-ai-rg-$LOCATION"
$PG_ADMIN_USERNAME="pgAdmin"
$PG_ADMIN_PASSWORD="eS9soB8BYJlMQuln"
$PG_SERVER_NAME = "psql-learn-$LOCATION-kr2shcyizikyg"
$DB_NAME = "rentals"
# $TEMPLATE_LOCATION = ".\my-mslearn-postgresql\Allfiles\Labs\Shared\deploy.bicep"
$TEMPLATE_LOCATION = ".\mslearn-postgresql\Allfiles\Labs\Shared\deploy.bicep"

# set your default subscription
# get your subscriptions 
$SUBSCRIPTIONS = az account subscription list
$SUBSCRIPTIONS_CONVERTED = ConvertFrom-JSON -InputObject "$SUBSCRIPTIONS"
# if you have only one subsription
$YOUR_SUBSCRIPTION_ID = $SUBSCRIPTIONS_CONVERTED[0].subscriptionId

az account set --subscription $YOUR_SUBSCRIPTION_ID

# create resource group 
az group create --name $RESOURCEGROUP --location $LOCATION

# create all needed resources
$CREATED_RESOURCES = az deployment group create --resource-group $RESOURCEGROUP --template-file $TEMPLATE_LOCATION --parameters restore=false adminLogin=$PG_ADMIN_USERNAME adminLoginPassword=$PG_ADMIN_PASSWORD
# convert to object for easy use
$CREATED_RESOURCES_CONVERTED = ConvertFrom-Json -InputObject "$CREATED_RESOURCES"

#-----------------------------------------------------------------------
# Connecting to Azure PostgreSQL database locally
#-----------------------------------------------------------------------

# Download PostgeSQL installer from https://www.postgresql.org/download/
# Run the intaller and schoose to install 'Command Line Tools'. Finish installation. 

# Open new PS window
# Go to PostgreSQL bin folder. (the path is set during installation)
cd 'C:\Program Files\PostgreSQL\17\bin'

$PG_SERVER_HOST = az postgres flexible-server show --resource-group $RESOURCEGROUP --name $PG_SERVER_NAME  --query fullyQualifiedDomainName  --output tsv

# Connect to to Postge SQL DB
./psql.exe --host=$PG_SERVER_HOST  --port=5432 --username=$PG_ADMIN_USERNAME --dbname=$DB_NAME --set=sslmode=require


#-----------------------------------------------------------------------
# PostgreSQL DB Setup: Configure extensions
#-----------------------------------------------------------------------

# enable extensions in postgres DB 
# https://learn.microsoft.com/en-us/azure/postgresql/extensions/how-to-allow-extensions?tabs=allow-extensions-azure-resource-manager%2Cload-libraries-portal#how-to-use-postgresql-extensions
az postgres flexible-server parameter set --resource-group $RESOURCEGROUP  --server-name $PG_SERVER_NAME --subscription $YOUR_SUBSCRIPTION_ID --name azure.extensions --value azure_ai,vector

# AI Extension
SHOW azure.extensions;
# azure_ai and vector must be in the extension list

# enable vecor extension
CREATE EXTENSION vector;

# enable azure_ai extansion
CREATE EXTENSION azure_ai;

# get openai resource keys 
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

#-----------------------------------------------------------------------
# Populate the database with sample data
#-----------------------------------------------------------------------

# create listings table:
DROP TABLE IF EXISTS listings;
    
 CREATE TABLE listings (
     id int,
     name varchar(100),
     description text,
     property_type varchar(25),
     room_type varchar(30),
     price numeric,
     weekly_price numeric
 );

 # create reviews table:

 DROP TABLE IF EXISTS reviews;
    
 CREATE TABLE reviews (
     id int,
     listing_id int, 
     date date,
     comments text
 );

# you must provide full path to the CSV files
# <my-repo-path>  is the full path of the repo folder 
\COPY listings FROM <my-repo-path>/my-mslearn-postgresql/Allfiles/Labs/Shared/listings.csv CSV HEADER;
\COPY reviews FROM ./mslearn-postgresql/Allfiles/Labs/Shared/reviews.csv CSV HEADER;

#-----------------------------------------------------------------------
# Create and store embedding vectors
#-----------------------------------------------------------------------

# Add the embedding vector column.
ALTER TABLE listings ADD COLUMN listing_vector vector(1536);

# Generate an embedding vector for the description of each listing

 UPDATE listings
 SET listing_vector = azure_openai.create_embeddings('embedding', description, max_attempts => 5, retry_delay_ms => 500)
 WHERE listing_vector IS NULL;

 #check the result 
  SELECT listing_vector FROM listings LIMIT 1;

#-----------------------------------------------------------------------
# Perform a semantic search query
#-----------------------------------------------------------------------

SELECT id, name FROM listings ORDER BY listing_vector <=> azure_openai.create_embeddings('embedding', 'bright natural light')::vector LIMIT 10;
SELECT id, description FROM listings ORDER BY listing_vector <=> azure_openai.create_embeddings('embedding', 'bright natural light')::vector LIMIT 1;
 
#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
