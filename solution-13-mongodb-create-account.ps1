<#
**********************************************************
Implement vCore-based Azure Cosmos DB for MongoDB 
**********************************************************
#>

#**********************************************************
# Exercise 1 - Deploy a vCore-based Azure Cosmos DB for MongoDB cluster
# https://github.com/MicrosoftLearning/mslearn-cosmosdb-mongodb-vcore/blob/master/Instructions/01-create-account.md
#**********************************************************

# CONFIG
# Cluster tier 'Free' is not currently available in region 'northeurope'.
# 'Free tier is currently available in the South India region only.' (2025-01-02)
# https://learn.microsoft.com/en-us/azure/cosmos-db/mongodb/vcore/free-tier
$LOCATION="southindia"
$RESOURCEGROUP="ld-learn-mongodb-ai-rg-$LOCATION"
$MONGODB_CLUSTER_NAME="ld-learn-mongodb-cluster"
$MONGODB_CLUSTER_USERNAME="cosmosClusterAdmin"
$MONGODB_CLUSTER_PASSWORD="eS9soB8BYJlMQuln"

# set your default subscription
# get your subscriptions 
$SUBSCRIPTIONS = az account subscription list
$SUBSCRIPTIONS_CONVERTED = ConvertFrom-JSON -InputObject "$SUBSCRIPTIONS"
# if you have only one subsription
$YOUR_SUBSCRIPTION_ID = $SUBSCRIPTIONS_CONVERTED[0].subscriptionId

az account set --subscription $YOUR_SUBSCRIPTION_ID

# create resource group 
az group create --name $RESOURCEGROUP --location $LOCATION
az configure --defaults group=$RESOURCEGROUP

# create mongodb cluster
$MONGODB_CLUSTER_RESOURCE = az cosmosdb mongocluster create --location $LOCATION --cluster-name $MONGODB_CLUSTER_NAME --administrator-login $MONGODB_CLUSTER_USERNAME --administrator-login-password $MONGODB_CLUSTER_PASSWORD  --server-version 6.0 --shard-node-tier "Free" --shard-node-count 1 --shard-node-ha false --shard-node-disk-size-gb 32
$MONGODB_CLUSTER_RESOURCE_CONVERTED = ConvertFrom-JSON -InputObject "$MONGODB_CLUSTER_RESOURCE"
$MONGODB_CONNECTION_STRING_TEMPLATE = $MONGODB_CLUSTER_RESOURCE_CONVERTED.properties.connectionString

az cosmosdb mongocluster firewall rule create --cluster-name $MONGODB_CLUSTER_NAME --resource-group $RESOURCEGROUP --rule-name "allow-all-ips"  --start-ip-address 0.0.0.0  --end-ip-address 255.255.255.255

#-----------------------------------------------------------------------
# Connecting to Azure MongoDB locally
#-----------------------------------------------------------------------

# Follow instruction to install mongosh with msi file
# https://www.mongodb.com/docs/mongodb-shell/install/

# Open Powershell (or any terminal)

# Connect to MongoDB Account using azure connection string 
# Prepare Connection String 
$MONGODB_CONNECTION_STRING = $MONGODB_CONNECTION_STRING_TEMPLATE.replace('<user>',$MONGODB_CLUSTER_USERNAME)
$MONGODB_CONNECTION_STRING = $MONGODB_CONNECTION_STRING.replace('<password>',$MONGODB_CLUSTER_PASSWORD)

# run 
mongosh $MONGODB_CONNECTION_STRING

#**********************************************************
# Add Database, Collection and sample data
#**********************************************************

# Execute following commands in shell (locally in mongosh shell): 
use quickstartDB
db.createCollection('sampleCollection')

# load data
db.sampleCollection.insertMany([
    {title: "The Great Gatsby", author: "F. Scott Fitzgerald", pages: 180},
    {title: "To Kill a Mockingbird", author: "Harper Lee", pages: 324},
    {title: "1984", author: "George Orwell", pages: 328},
    {title: "The Catcher in the Rye", author: "J.D. Salinger", pages: 277},
    {title: "Moby-Dick", author: "Herman Melville", pages: 720},
    {title: "Pride and Prejudice", author: "Jane Austen", pages: 279},
    {title: "The Hobbit", author: "J.R.R. Tolkien", pages: 310},
    {title: "War and Peace", author: "Leo Tolstoy", pages: 1392},
    {title: "The Odyssey", author: "Homer", pages: 374},
    {title: "Ulysses", author: "James Joyce", pages: 730}
  ])

# Query to find all books written by "George Orwell"
db.sampleCollection.find({author: "George Orwell"})
# Query to find all books with more than 500 pages
db.sampleCollection.find({pages: {$gt: 500}})
# Query to find all books and sort them by the number of pages in ascending order
db.sampleCollection.find({}).sort({pages: 1})

#**********************************************************
# CLEANUP
az group delete --name $RESOURCEGROUP -y

# permanently delete deleted accounts (needed for cognitiveservices accounts): 
$deletedAccounts = az cognitiveservices account list-deleted
$deletedAccounts | ConvertFrom-Json | ForEach-Object {az resource delete --ids $_.id}
