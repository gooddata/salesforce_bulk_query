Salesforce Bulk Query
=====================
A library for downloading data from Salesforce Bulk API. We only focus on querying, other operations of the API aren't supported. Designed to handle a lot of data.

Derived from [Salesforce Bulk API](https://github.com/yatish27/salesforce_bulk_api)

## Status

[![Gem Version](https://badge.fury.io/rb/salesforce_bulk_query.png)](http://badge.fury.io/rb/salesforce_bulk_query)
[![Downloads](http://img.shields.io/gem/dt/salesforce_bulk_query.svg)](http://rubygems.org/gems/salesforce_bulk_query)
[![Dependency Status](https://gemnasium.com/cvengros/salesforce_bulk_query.png)](https://gemnasium.com/cvengros/salesforce_bulk_query)
[![Code Climate](https://codeclimate.com/github/cvengros/salesforce_bulk_query.png)](https://codeclimate.com/github/cvengros/salesforce_bulk_query)
[![Build Status](https://travis-ci.org/cvengros/salesforce_bulk_query.png)](https://travis-ci.org/cvengros/salesforce_bulk_query)
[![Coverage Status](https://coveralls.io/repos/cvengros/salesforce_bulk_query/badge.png)](https://coveralls.io/r/cvengros/salesforce_bulk_query)

## Basic Usage
To install, run:

    gem install salesforce_bulk_query

or add

    gem salesforce_bulk_query

to your Gemfile.

Before using the library, make sure you have the right account in your Salesforce organization that has access to API and that you won't run out of the [API limits](http://www.salesforce.com/us/developer/docs/api_asynchpre/Content/asynch_api_concepts_limits.htm#batch_proc_time_title). 

You will also need a Salesforce connected app for the `client_id` and `client_secret` params, see [the guide](https://help.salesforce.com/HTViewHelpDoc?id=connected_app_create.htm&language=en_US). The app needs to have OAuth settings enabled (even if you plan to use just username-password-token authentication). The required permissions are _Access and manage your data (api)_, _Perform requests on your behalf at any time (refresh token, offline access)_. The other parameters such as redirect url don't need to be set.

For doing most of the API calls, the library uses [Restforce](https://github.com/ejholmes/restforce) Code example:

```ruby
require 'restforce'
require 'salesforce_bulk_query'

# Create a restforce client instance
# with basic auth
restforce = Restforce.new(
  :username => 'me',
  :password => 'password',
  :security_token => 'token',
  :client_id => "my sfdc app client id",
  :client_secret => "my sfdc app client secret"
)

# or OAuth
restforce = Restforce.new(
  :refresh_token => "xyz",
  :client_id => "my sfdc app client id",
  :client_secret => "my sfdc app client secret"
)

bulk_api = SalesforceBulkQuery::Api.new(restforce)

# query the api
result = bulk_api.query("Task", "SELECT Id, Name FROM Task")

# the result is files 
puts "All the downloaded stuff is in csvs: #{result[:filenames]}"

# query is a blocking call and can take several hours
# if you want to just start the query asynchronously, use 
query = start_query("Task", "SELECT Id, Name FROM Task")

# get a coffee
sleep(1234)

# get what's available and check the status
results = query.get_available_results
if results[:succeeded]
  puts "All the downloaded stuff is in csvs: #{results[:filenames]}"
else
  puts "This is going to take a while, get another coffee"
end
```

## How it works

The library uses the [Salesforce Bulk API](https://www.salesforce.com/us/developer/docs/api_asynch/index_Left.htm#CSHID=asynch_api_bulk_query.htm|StartTopic=Content%2Fasynch_api_bulk_query.htm|SkinName=webhelp). The given query is divided into 15 subqueries, according to the [limits](http://www.salesforce.com/us/developer/docs/api_asynchpre/Content/asynch_api_concepts_limits.htm#batch_proc_time_title). Each subquery is an interval based on the CreatedDate Salesforce field (date field can be customized). The limits are passed to the API in SOQL queries. Subqueries are sent to the API as batches and added to a job. 

The first interval starts with the date the first Salesforce object was created, we query Salesforce REST API for that. If this query times out, we use a constant. The last interval ends a few minutes before now to avoid consistency issues. Custom start and end can be passed - see Options.

Job has a fixed time limit to process all the subqueries. Batches that finish in time are downloaded to CSVs, batches that don't are divided to 15 subqueries each and added to new jobs.

CSV results are downloaded by chunks, so that we don't run into memory related issues. All other requests are made through the Restforce client that is passed when instantiating the Api class. Restforce is not in the dependencies, so theoretically you can pass another object with the same set of methods as Restforce client.

## Options
There are a few optional settings you can pass to the `Api` methods:
* `api_version`: Which Salesforce api version should be used
* `logger`: Where logs should go, see the example.
* `filename_prefix`: Prefix applied to csv files.
* `directory_path`: Custom direcotory path for CSVs, if omitted, a new temp directory is created.
* `check_interval`: How often the results should be checked in secs. 
* `time_limit`: Maximum time the query can take. If this time limit is exceeded, available results are downloaded and the list of subqueries that didn't finished is returned. In seconds. The limti should be understood as limit for waiting. When the limit is reached the function downloads data that is ready which can take some additonal time. If no limit is given the query runs until it finishes.
* `date_field`: Salesforce date field that will be used for splitting the query, and optionally limiting the results. Must be a date field on the queried sobject. Default is `CreatedDate`
* `date_from`, `date_to`: limits for the `date_field` (`CreatedDate` by default). Note that queries can't contain any WHERE statements as we're doing some manipulations to create subqueries and we don't want things to get too difficult. So this is the way to limit the query yourself. The format is like `"1999-01-01T00:00:00.000Z"`
* `single_batch`: If true, the queries are not divided into subqueries as described above. Instead one batch job is created with the given query. This is faster for small amount of data, but will fail with a timeout if you have a lot of data. 

See specs for exact usage.

## Logging

```ruby
require 'logger'
require 'restforce'

# create the restforce client
restforce = Restforce.new(...)

# instantiate a logger and pass it to the Api constructor
logger = Logger.new(STDOUT)
bulk_api = SalesforceBulkQuery::Api.new(restforce, :logger => logger)

# switch off logging in Restforce so you don't get every message twice
Restforce.log = false
```

If you're using Restforce as a client (which you probably are) and you want to do logging, Salesforce Bulk Query will use a custom logging middleware for Restforce. This is because the original logging middleware puts all API responses to log, which is not something you would like to do for a few gigabytes CSVs. When you use the :logger parameter it's recommended you switch off the default logging in Restforce, otherwise you'll get all messages twice. 

## Notes

Query (user given) -> Job (Salesforce construct that encapsulates 15 batches) -> Batch (1 SOQL with Date constraints)

At the beginning the query is divided into 15 subqueries and put into a single job. When one of the subqueries fails, a new job with 15 subqueries is created, the range of the failed query is divided into 15 sub-subqueries.

## Change policy

The gem is trying to follow [semantic versioning](http://semver.org/). All  methods and options described in this readme document are considered public API. If any of these change, at least the minor version is bumped. Methods and their params not described in this document can change even in patches.

## Running tests locally
Travis CI is set up for this repository to make sure all the tests are passing with each commit.

To run the tests locally:

* Copy the env_setup-example.sh file
```
cp  env_setup-example.sh env_setup.sh
```
* Setup all the params in env_setup. USERNAME, PASSWORD and TOKEN are your salesforce account credentials. You can get those by [registering for a free developer account](https://developer.salesforce.com/signup). You might need to [reset your security token](https://help.salesforce.com/apex/HTViewHelpDoc?id=user_security_token.htm) to put it to TOKEN variable. CLIENT_ID and CLIENT_SECRET belong to your Salesforce connected app. You can create one by following the steps outlined in [the tutorial](https://help.salesforce.com/apex/HTViewHelpDoc?id=connected_app_create.htm). Make sure you check the 'api' permission.
* Run the env_setup
```
. env_setup.sh
```
* Run the tests
```
bundle exec rspec
```

Note that env_setup.sh is ignored from git in .gitignore so that you don't commit your credentials by accident.

## Contributing

1. Fork it ( https://github.com/[my-github-username]/salesforce_bulk_query/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Run the tests (see above), fix if they fail.
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

Make sure you run all the tests and they pass. If you create a new feature, write a test for it. 

## Copyright

Copyright (c) 2014 Yatish Mehta & GoodData Corporation. See [LICENSE](LICENSE) for details.



