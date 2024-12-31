<#
**********************************************************
Summarize data with Azure AI Services and Azure database for PostgreSQL
**********************************************************
#>

#**********************************************************
# Exercise 1 - Perform Extractive and Abstractive Summarization
# https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/15-perform-extractive-and-abstractive-summarization.html
#**********************************************************

# Follow ./solution-6-postgresql-semantic-search-1.ps1 to create necessary resources and data
# No need to cenable vector extansion and create vectors

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

#**********************************************************
# Review the Summarization Capabilities of the Extension
#**********************************************************

# in rental DB: 
# improve readability
\x auto

# examine function for extractive summary
\df azure_cognitive.summarize_extractive

#**********************************************************
# Create Summaries for Property Descriptions
#**********************************************************
# extractive summary: 

 SELECT
     id,
     name,
     description,
     azure_cognitive.summarize_extractive(description, 'en', 2) AS extractive_summary
 FROM listings
 WHERE id IN (1, 2);

 #abstractive summary

 SELECT
     id,
     name,
     description,
     azure_cognitive.summarize_abstractive(description, 'en', 2) AS abstractive_summary
 FROM listings
 WHERE id IN (1, 2);

 # side-by-side comparison

  SELECT
     id,
     azure_cognitive.summarize_extractive(description, 'en', 2) AS extractive_summary,
     azure_cognitive.summarize_abstractive(description, 'en', 2) AS abstractive_summary
 FROM listings
 WHERE id IN (1, 2);

#**********************************************************
# Store Description Summary in the Database
#**********************************************************

 ALTER TABLE listings
 ADD COLUMN summary text;

# creating summaries in  batches
WITH batch_cte AS (
     SELECT azure_cognitive.summarize_abstractive(ARRAY(SELECT description FROM listings ORDER BY id), 'en', batch_size => 25) AS summary
 ),
 summary_cte AS (
     SELECT
         ROW_NUMBER() OVER () AS id,
         ARRAY_TO_STRING(summary, ',') AS summary
     FROM batch_cte
 )
 UPDATE listings AS l
 SET summary = s.summary
 FROM summary_cte AS s
 WHERE l.id = s.id;

 # get result
  SELECT
     id,
     name,
     description,
     summary
 FROM listings
 LIMIT 5;

#**********************************************************
# Store Description Summary in the Database
#**********************************************************

 SELECT unnest(azure_cognitive.summarize_abstractive(reviews_combined, 'en')) AS review_summary
 FROM (
     -- Combine all reviews for a listing
     SELECT string_agg(comments, ' ') AS reviews_combined
     FROM reviews
     WHERE listing_id = 1
 );
 
#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
