<#
**********************************************************
Use Azure Machine Learning for inferencing from Azure Database for PostgreSQL  
**********************************************************
#>

#**********************************************************
# Exercise 1 - Perform inference using Azure Machine Learning
# https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/19-perform-inference-azure-machine-learning.html
#**********************************************************

# CONFIG
# region must support abstractive summarization
# https://learn.microsoft.com/en-us/azure/ai-services/language-service/summarization/region-support
$LOCATION="uksouth"
$RESOURCEGROUP="ld-learn-postgresql-ai-rg-$LOCATION"
$PG_ADMIN_USERNAME="pgAdmin"
$PG_ADMIN_PASSWORD="eS9soB8BYJlMQuln"
# $TEMPLATE_LOCATION = ".\my-mslearn-postgresql\Allfiles\Labs\Shared\deploy-azure-machine-learning.bicep"
$TEMPLATE_LOCATION = ".\mslearn-postgresql\Allfiles\Labs\Shared\deploy-azure-machine-learning.bicep"

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
$CREATED_RESOURCES = az deployment group create --resource-group $RESOURCEGROUP --template-file $TEMPLATE_LOCATION --parameters adminLogin=$PG_ADMIN_USERNAME adminLoginPassword=$PG_ADMIN_PASSWORD
# convert to object for easy use
$CREATED_RESOURCES_CONVERTED = ConvertFrom-Json -InputObject "$CREATED_RESOURCES"

$PG_SERVER_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.serverName.value
$DB_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.databaseName.value # or see bicep template file
$ML_WORKSPACEL_NAME = $CREATED_RESOURCES_CONVERTED.properties.outputs.azureMLWorkspaceName.value

#-----------------------------------------------------------------------
# Deploy an Azure Machine Learning model
#-----------------------------------------------------------------------

$DEMO_MODEL_FOLDER_NAME = "mlflow-model"
$DEMO_MODEL_ZIP_PATH = ".\mslearn-postgresql\Allfiles\Labs\Shared\$DEMO_MODEL_NAME.zip"
$DEMO_MODEL_LOCATION = ".\mslearn-postgresql\Allfiles\Labs\Shared"
$ML_MODEL_NAME = "RentalListings"
$ML_MODEL_PATH = "./mslearn-postgresql/Allfiles/Labs/Shared/" + $DEMO_MODEL_FOLDER_NAME

Expand-Archive -Path $DEMO_MODEL_ZIP_PATH -DestinationPath $DEMO_MODEL_LOCATION

$ML_MODEL = az ml model create --name $ML_MODEL_NAME  --version 1 --path $ML_MODEL_PATH --resource-group $RESOURCEGROUP --workspace-name $ML_WORKSPACEL_NAME --type "mlflow_model" 

# deploy the model as real Time endpoint using ML Studio in ml.azure.com
# TODO: describe how to deploy using CLI.

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
CREATE EXTENSION IF NOT EXISTS azure_ai;

# link azure_cognitive extension with azure cognitive service 
# Set settings in psql

$ML_WORKSAPCE_ENDPOINTS = az ml online-endpoint list --resource-group $RESOURCEGROUP --workspace-name $ML_WORKSPACEL_NAME
$ML_WORKSAPCE_ENDPOINTS_CONVERTED = ConvertFrom-Json -InputObject "$ML_WORKSAPCE_ENDPOINTS"
# if you have only one endpoint
$ML_WORKSAPCE_ENDPOINT_NAME = $ML_WORKSAPCE_ENDPOINTS_CONVERTED[0].name

$ML_WORKSAPCE_ENDPOINT_ENDPOINT = az ml online-endpoint show --name $ML_WORKSAPCE_ENDPOINT_NAME --resource-group $RESOURCEGROUP --workspace-name $ML_WORKSPACEL_NAME --query "scoring_uri" --output tsv
$ML_WORKSAPCE_ENDPOINT_KEY = az ml online-endpoint get-credentials --name $ML_WORKSAPCE_ENDPOINT_NAME --resource-group $RESOURCEGROUP --workspace-name $ML_WORKSPACEL_NAME --query "primaryKey" --output tsv

$ML_WORKSAPCE_ENDPOINT_ENDPOINT | Clip
# paste as {endpoint}
SELECT azure_ai.set_setting('azure_ml.scoring_endpoint','{endpoint}');

$ML_WORKSAPCE_ENDPOINT_KEY | Clip
# paste as {key}
SELECT azure_ai.set_setting('azure_ml.endpoint_key', '{key}');

# check if it was set correctly 
SELECT azure_ai.get_setting('azure_ml.scoring_endpoint');
SELECT azure_ai.get_setting('azure_ml.endpoint_key');

#-----------------------------------------------------------------------
# Populate the database with sample data
#-----------------------------------------------------------------------

 # create listings_to_price table:

DROP TABLE IF EXISTS listings_to_price;
    
 CREATE TABLE listings_to_price (
     id INT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
     host_is_superhost INT NOT NULL,
     host_has_profile_pic INT NOT NULL,
     host_identity_verified INT NOT NULL,
     neighbourhood_group_cleansed VARCHAR(75) NOT NULL,
     zipcode VARCHAR(5) NOT NULL,
     property_type VARCHAR(30) NOT NULL,
     room_type VARCHAR(30) NOT NULL,
     accommodates INT NOT NULL,
     bathrooms DECIMAL(3,1) NOT NULL,
     bedrooms INT NOT NULL,
     beds INT NOT NULL
 );

# add data
 INSERT INTO listings_to_price(host_is_superhost, host_has_profile_pic, host_identity_verified,
     neighbourhood_group_cleansed, zipcode, property_type, room_type,
     accommodates, bathrooms, bedrooms, beds)
 VALUES
     (1, 1, 1, 'Queen Anne', '98119', 'House', 'Private room', 2, 1.0, 1, 1),
     (0, 1, 1, 'University District', '98105', 'Apartment', 'Entire home/apt', 4, 1.5, 2, 2),
     (0, 0, 0, 'Central Area', '98122', 'House', 'Entire home/apt', 4, 1.5, 3, 3),
     (0, 0, 0, 'Downtown', '98101', 'House', 'Entire home/apt', 4, 1.5, 3, 3),
     (0, 0, 0, 'Capitol Hill', '98122', 'House', 'Entire home/apt', 4, 1.5, 3, 3);

#**********************************************************
# Review Extension Functions
#**********************************************************

# in rental DB: 
# improve readability
\x auto

# examine function
\df azure_ml.inference

#**********************************************************
# Create a stored procedure to translate listings data
#**********************************************************

# create a new function named price_listing 
 CREATE OR REPLACE FUNCTION price_listing (
     IN host_is_superhost INT, IN host_has_profile_pic INT, IN host_identity_verified INT,
     IN neighbourhood_group_cleansed VARCHAR(75), IN zipcode VARCHAR(5), IN property_type VARCHAR(30),
     IN room_type VARCHAR(30), IN accommodates INT, IN bathrooms DECIMAL(3,1), IN bedrooms INT, IN beds INT)
 RETURNS DECIMAL(6,2)
 AS $$
     SELECT CAST(jsonb_array_elements(inference.inference) AS DECIMAL(6,2)) AS expected_price
     FROM azure_ml.inference(('
     {
         "input_data": {
             "columns": [
                 "host_is_superhost",
                 "host_has_profile_pic",
                 "host_identity_verified",
                 "neighbourhood_group_cleansed",
                 "zipcode",
                 "property_type",
                 "room_type",
                 "accommodates",
                 "bathrooms",
                 "bedrooms",
                 "beds"
             ],
             "index": [0],
             "data": [["' || host_is_superhost || '", "' || host_has_profile_pic || '", "' || host_identity_verified || '", "' ||
             neighbourhood_group_cleansed || '", "' || zipcode || '", "' || property_type || '", "' || room_type || '", ' ||
             accommodates || ', ' || bathrooms || ', ' || bedrooms || ', ' || beds || ']]
         }
     }')::jsonb, deployment_name=>'rentallistings-1');
 $$ LANGUAGE sql;

# Execute the function
SELECT * FROM price_listing(0, 0, 0, 'Central Area', '98122', 'House', 'Entire home/apt', 4, 1.5, 3, 3);

# Call the function for each row in the listings_to_price
 SELECT l2p.*, expected_price
 FROM listings_to_price l2p
     CROSS JOIN LATERAL price_listing(l2p.host_is_superhost, l2p.host_has_profile_pic, l2p.host_identity_verified,
         l2p.neighbourhood_group_cleansed, l2p.zipcode, l2p.property_type, l2p.room_type,
         l2p.accommodates, l2p.bathrooms, l2p.bedrooms, l2p.beds) expected_price;

#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
