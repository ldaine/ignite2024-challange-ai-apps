<#
**********************************************************
Translate Text with Azure AI Translator and Azure Database for PostgreSQL 
**********************************************************
#>

#**********************************************************
# Exercise 1 -Translate Text with Azure AI Translator
# https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/18-translate-text.html
#**********************************************************

# CONFIG
# region must support abstractive summarization
# https://learn.microsoft.com/en-us/azure/ai-services/language-service/summarization/region-support
$LOCATION="uksouth"
$RESOURCEGROUP="ld-learn-postgresql-ai-rg-$LOCATION"
$PG_ADMIN_USERNAME="pgAdmin"
$PG_ADMIN_PASSWORD="eS9soB8BYJlMQuln"
# $TEMPLATE_LOCATION = ".\my-mslearn-postgresql\Allfiles\Labs\Shared\deploy-translate.bicep"
$TEMPLATE_LOCATION = ".\mslearn-postgresql\Allfiles\Labs\Shared\deploy-translate.bicep"

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

$PG_SERVER_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.serverName.value
$DB_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.databaseName.value # or see bicep template file

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

#----------------------------------------------------------------------
# Install and configure the azure_ai extension
#-----------------------------------------------------------------------

# enable extensions in postgres DB 
# https://learn.microsoft.com/en-us/azure/postgresql/extensions/how-to-allow-extensions?tabs=allow-extensions-azure-resource-manager%2Cload-libraries-portal#how-to-use-postgresql-extensions
az postgres flexible-server parameter set --resource-group $RESOURCEGROUP  --server-name $PG_SERVER_NAME --subscription $YOUR_SUBSCRIPTION_ID --name azure.extensions --value azure_ai,vector

# AI Extension
SHOW azure.extensions;
# azure_ai and vector must be in the extension list

# enable azure_ai extansion
CREATE EXTENSION azure_ai;

# link azure_cognitive extension with azure cognitive service 
# Set settings in psql
$COGNITIVE_SERVICE_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.translatorServiceName.value
$COGNITIVE_SERVICE_ENDPOINT = az cognitiveservices account show --name $COGNITIVE_SERVICE_NAME --resource-group $RESOURCEGROUP --query "properties.endpoints.DocumentTranslation" --output tsv
$COGNITIVE_SERVICE_REGION = az cognitiveservices account show --name $COGNITIVE_SERVICE_NAME --resource-group $RESOURCEGROUP --query "location" --output tsv
$COGNITIVE_KEYS = az cognitiveservices account keys list --name $COGNITIVE_SERVICE_NAME --resource-group $RESOURCEGROUP
$COGNITIVE_KEYS_CONVERTED = ConvertFrom-JSON -InputObject "$COGNITIVE_KEYS"
$COGNITIVE_SERVICE_ENDPOINT | Clip
# paste as {endpoint}
SELECT azure_ai.set_setting('azure_cognitive.endpoint', '{endpoint}');

$COGNITIVE_KEYS_CONVERTED.key1 | Clip
# paste as {api-key}
SELECT azure_ai.set_setting('azure_cognitive.subscription_key', '{api-key}');

# region should be equal to $LOCATION
$COGNITIVE_SERVICE_REGION | Clip
SELECT azure_ai.set_setting('azure_cognitive.region', '{region}');

# check if it was set correctly 
SELECT azure_ai.get_setting('azure_cognitive.endpoint');
SELECT azure_ai.get_setting('azure_cognitive.subscription_key');
SELECT azure_ai.get_setting('azure_cognitive.region');

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

# you must provide full path to the CSV files
 \COPY listings FROM ./mslearn-postgresql/Allfiles/Labs/Shared/listings.csv CSV HEADER

 # Create additional tables for translation

  CREATE TABLE languages (
     code VARCHAR(7) NOT NULL PRIMARY KEY
 );

  CREATE TABLE listing_translations(
     id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
     listing_id INT,
     language_code VARCHAR(7),
     description TEXT
 );

  INSERT INTO languages(code)
 VALUES
     ('de'),
     ('zh-Hans'),
     ('hi'),
     ('hu'),
     ('sw');

#**********************************************************
# Review Extension Functions
#**********************************************************

# in rental DB: 
# improve readability
\x auto

# examine function
\df azure_cognitive.translate


#**********************************************************
# Create a stored procedure to translate listings data
#**********************************************************

# exaaple 
SELECT
     id,
     name,
     azure_cognitive.translate(name, 'de') AS name_de
 FROM listings
 WHERE id <= 5
 ORDER BY id;

# create a stored procedure to load data in batches
 CREATE OR REPLACE PROCEDURE translate_listing_descriptions(max_num_listings INT DEFAULT 10)
 LANGUAGE plpgsql
 AS $$
 BEGIN
     WITH batch_to_load(id, description) AS
     (
         SELECT id, description
         FROM listings l
         WHERE NOT EXISTS (SELECT * FROM listing_translations ll WHERE ll.listing_id = l.id)
         LIMIT max_num_listings
     )
     INSERT INTO listing_translations(listing_id, language_code, description)
     SELECT b.id, l.code, (unnest(tr.translations)).TEXT
     FROM batch_to_load b
         CROSS JOIN languages l
         CROSS JOIN LATERAL azure_cognitive.translate(b.description, l.code) tr;
 END;
 $$;

 # Execute the stored procedure using the following SQL command
CALL translate_listing_descriptions(10);

# Run the following script to get the count of listing translations
SELECT COUNT(*) FROM listing_translations;

#**********************************************************
# Create a procedure to add a new listing with translations
#**********************************************************

 CREATE OR REPLACE PROCEDURE add_listing(id INT, name VARCHAR(255), description TEXT)
 LANGUAGE plpgsql
 AS $$
 DECLARE
 listing_id INT;
 BEGIN
     INSERT INTO listings(id, name, description)
     VALUES(id, name, description);

     INSERT INTO listing_translations(listing_id, language_code, description)
     SELECT id, l.code, (unnest(tr.translations)).TEXT
     FROM languages l
         CROSS JOIN LATERAL azure_cognitive.translate(description, l.code) tr;
 END;
 $$;

# Execute the stored procedure using the following SQL command:

CALL add_listing(51, 'A Beautiful Home', 'This is a beautiful home in a great location.');

# Run the following script to get the translations for your new listing.

 SELECT l.id, l.name, l.description, lt.language_code, lt.description AS translated_description
 FROM listing_translations lt
     INNER JOIN listings l ON lt.listing_id = l.id
 WHERE l.name = 'A Beautiful Home';

#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
