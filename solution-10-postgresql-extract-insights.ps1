<#
**********************************************************
Extract insights using Azure AI Language and Azure Database for PostgreSQL  
**********************************************************
#>

#**********************************************************
# Exercise 1 - Extract insights using the Azure AI Language service with Azure Database for PostgreSQL
# https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/17-extract-insights-azure-ai-language-azure-database-postgresql.html
#**********************************************************

# Follow ./solution-6-postgresql-semantic-search-1.ps1 to create necessary resources and data

#**********************************************************
# Review Extension Functions
#**********************************************************

# in rental DB: 
# improve readability
\x auto

# examine function
\df azure_cognitive.extract_key_phrases
\df azure_cognitive.recognize_entities
\df azure_cognitive.recognize_pii_entities
\d azure_cognitive.pii_entity_recognition_result


#**********************************************************
# Extract key phrases
#**********************************************************

# example function call
SELECT
     id,
     azure_cognitive.extract_key_phrases(description) AS key_phrases
 FROM listings
 WHERE id <= 5
 ORDER BY id;

# create column for key phrases

 ALTER TABLE listings ADD COLUMN key_phrases text[];

 # Populate the column in batches

 UPDATE listings
 SET key_phrases = azure_cognitive.extract_key_phrases(description)
 FROM (SELECT id FROM listings WHERE key_phrases IS NULL ORDER BY id LIMIT 100) subset
 WHERE listings.id = subset.id;

 # Query listings by key phrases:
SELECT id, name FROM listings WHERE 'closet' = ANY(key_phrases);

#**********************************************************
# Named entity recognition
#**********************************************************
# example function call
SELECT
     id,
     azure_cognitive.recognize_entities(description, 'en-us') AS entities
 FROM listings
 WHERE id <= 5
 ORDER BY id;

 # Create a column to contain the key results.
 ALTER TABLE listings ADD COLUMN entities azure_cognitive.entity[];

# Populate the column in batches
UPDATE listings
 SET entities = azure_cognitive.recognize_entities(description, 'en-us')
 FROM (SELECT id FROM listings WHERE entities IS NULL ORDER BY id LIMIT 500) subset
 WHERE listings.id = subset.id;

 #query all listings’ entities to find properties with basements
SELECT id, name
 FROM listings, unnest(listings.entities) AS e
 WHERE e.text LIKE '%living%room%'
 LIMIT 10;

#**********************************************************
# PII Recognition
#**********************************************************
 # Create a column to contain the redacted text and another for the recognized entities
ALTER TABLE listings ADD COLUMN description_pii_safe text;
 ALTER TABLE listings ADD COLUMN pii_entities azure_cognitive.entity[];

# Populate the column in batches
 UPDATE listings
 SET
     description_pii_safe = pii.redacted_text,
     pii_entities = pii.entities
 FROM (SELECT id, description FROM listings WHERE description_pii_safe IS NULL OR pii_entities IS NULL ORDER BY id LIMIT 100) subset,
 LATERAL azure_cognitive.recognize_pii_entities(subset.description, 'en-us') as pii
 WHERE listings.id = subset.id;

# display listing descriptions with any potential PII redacted
 SELECT description_pii_safe
 FROM listings
 WHERE description_pii_safe IS NOT NULL
 LIMIT 1;
 
# You may also identify the entities recognized in PII; for example, using the identical listing as above
 SELECT entities
 FROM listings
 WHERE entities IS NOT NULL
 LIMIT 1;
 
#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
