<#
**********************************************************
Perform sentiment analysis and opinion mining with Azure Database for PostgreSQL 
**********************************************************
#>

#**********************************************************
# Exercise 1 - Analyze Sentiment
# https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/16-analyze-sentiment.html
#**********************************************************

# Follow ./solution-6-postgresql-semantic-search-1.ps1 to create necessary resources and data
# No need to cenable vector extansion and create vectors

#----------------------------------------------------------------------
# working with azure_cognitive extension
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

#-----------------------------------------------------------------------
# Populate the database with sample data
#-----------------------------------------------------------------------

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
\COPY reviews FROM ./mslearn-postgresql/Allfiles/Labs/Shared/reviews.csv CSV HEADER;

#**********************************************************
# Review the Analyze Sentiment Capabilities of the Extension
#**********************************************************

# in rental DB: 
# improve readability
\x auto

# examine function for extractive summary
\df azure_cognitive.analyze_sentiment

\dT+ azure_cognitive.sentiment_analysis_result

\d+ azure_cognitive.sentiment_analysis_result

#**********************************************************
# Analyze the sentiment of reviews
#**********************************************************

SELECT
     id,
     azure_cognitive.analyze_sentiment(comments, 'en') AS sentiment
 FROM reviews
 WHERE id <= 5
 ORDER BY id;

# for longer reviews

SELECT
     azure_cognitive.analyze_sentiment(ARRAY_REMOVE(STRING_TO_ARRAY(comments, '.'), ''), 'en') AS sentence_sentiments
 FROM reviews
 WHERE id = 1;

 # retrieve the underlying values

WITH cte AS (
     SELECT id, comments, azure_cognitive.analyze_sentiment(comments, 'en') AS sentiment FROM reviews
 )
 SELECT
     id,
     (sentiment).sentiment,
     (sentiment).positive_score,
     (sentiment).neutral_score,
     (sentiment).negative_score,
     comments
 FROM cte
 WHERE (sentiment).positive_score > 0.98
 LIMIT 5;

#**********************************************************
# Store Sentiment in the Reviews Table
#**********************************************************

 ALTER TABLE reviews
 ADD COLUMN sentiment varchar(10),
 ADD COLUMN positive_score numeric,
 ADD COLUMN neutral_score numeric,
 ADD COLUMN negative_score numeric;

# update the existing records in the reviews table
 WITH cte AS (
     SELECT id, azure_cognitive.analyze_sentiment(comments, 'en') AS sentiment FROM reviews
 )
 UPDATE reviews AS r
 SET
     sentiment = (cte.sentiment).sentiment,
     positive_score = (cte.sentiment).positive_score,
     neutral_score = (cte.sentiment).neutral_score,
     negative_score = (cte.sentiment).negative_score
 FROM cte
 WHERE r.id = cte.id;

 # same in batches

  WITH cte AS (
     SELECT azure_cognitive.analyze_sentiment(ARRAY(SELECT comments FROM reviews ORDER BY id), 'en', batch_size => 10) as sentiments
 ),
 sentiment_cte AS (
     SELECT
         ROW_NUMBER() OVER () AS id,
         sentiments AS sentiment
     FROM cte
 )
 UPDATE reviews AS r
 SET
     sentiment = (sentiment_cte.sentiment).sentiment,
     positive_score = (sentiment_cte.sentiment).positive_score,
     neutral_score = (sentiment_cte.sentiment).neutral_score,
     negative_score = (sentiment_cte.sentiment).negative_score
 FROM sentiment_cte
 WHERE r.id = sentiment_cte.id;

 # get result - searching for reviews with a negative sentiment, starting with the most negative first.
  SELECT
     id,
     negative_score,
     comments
 FROM reviews
 WHERE sentiment = 'negative'
 ORDER BY negative_score DESC;
 
#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
