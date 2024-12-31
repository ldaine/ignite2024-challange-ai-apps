<#
**********************************************************
Enable semantic search in Azure Database for PostgreSQL
**********************************************************
#>

#**********************************************************
# Exercise 2 - Create a search function for a recommendation system
# https://microsoftlearning.github.io/mslearn-postgresql/Instructions/Labs/14-create-search-function-recommendation-system.html
#**********************************************************

# Follow ./solution-6-postgresql-semantic-search-1.ps1 to create necessary resources and data

#**********************************************************
# Create the recommendation function
#**********************************************************

# in Rentals DB
CREATE FUNCTION
    recommend_listing(sampleListingId int, numResults int) 
RETURNS TABLE(
            out_listingName text,
            out_listingDescription text,
            out_score real)
AS $$ 
DECLARE
    queryEmbedding vector(1536); 
    sampleListingText text; 
BEGIN 
    sampleListingText := (
     SELECT
        name || ' ' || description
     FROM
        listings WHERE id = sampleListingId
    ); 

    queryEmbedding := (
     azure_openai.create_embeddings('embedding', sampleListingText, max_attempts => 5, retry_delay_ms => 500)
    );

    RETURN QUERY 
    SELECT
        name::text,
        description,
        -- cosine distance:
        (listings.listing_vector <=> queryEmbedding)::real AS score
    FROM
        listings 
    ORDER BY score ASC LIMIT numResults;
END $$
LANGUAGE plpgsql; 

#**********************************************************
# Query the recommendation function
#**********************************************************
select out_listingName, out_score from recommend_listing( (SELECT id from listings limit 1), 20); -- search for 20 listing recommendations closest to a listing

# To see the function runtime
az postgres flexible-server parameter set --resource-group $RESOURCEGROUP  --server-name $PG_SERVER_NAME --subscription $YOUR_SUBSCRIPTION_ID --name track_functions --value ALL

# Then, you can query the function statistics table:
SELECT * FROM pg_stat_user_functions WHERE funcname = 'recommend_listing';

 
#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
