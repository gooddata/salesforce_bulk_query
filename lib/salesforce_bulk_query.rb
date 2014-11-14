require 'salesforce_bulk_query/connection'
require 'salesforce_bulk_query/query'
require 'salesforce_bulk_query/logger'

# Module where all the stuff is happening
module SalesforceBulkQuery

  # Abstracts the whole library, class the user interacts with
  class Api
    @@DEFAULT_API_VERSION = '29.0'

    # Constructor
    # @param client [Restforce] An instance of the Restforce client, that is used internally to access Salesforce api
    # @param options
    def initialize(client, options={})
      @logger = options[:logger]

      api_version = options[:api_version] || @@DEFAULT_API_VERSION

      # use our own logging middleware if logger passed
      if @logger && client.respond_to?(:middleware)
        client.middleware.use(SalesforceBulkQuery::Logger, @logger, options)
      end

      # initialize connection
      @connection = SalesforceBulkQuery::Connection.new(client, api_version, @logger, options[:filename_prefix])
    end

    # Get the Salesforce instance URL
    def instance_url
      # make sure it ends with /
      url = @connection.client.instance_url
      url += '/' if url[-1] != '/'
      return url
    end

    CHECK_INTERVAL = 10
    QUERY_TIME_LIMIT = 60 * 60 * 2 # two hours

    # Query the Salesforce API. It's a blocking method - waits until the query is resolved
    # can take quite some time
    # @param sobject Salesforce object, e.g. "Opportunity"
    # @param soql SOQL query, e.g. "SELECT Name FROM Opportunity"
    # @return hash with :filenames and other useful stuff
    def query(sobject, soql, options={})
      check_interval = options[:check_interval] || CHECK_INTERVAL
      time_limit = options[:time_limit] || QUERY_TIME_LIMIT

      start_time = Time.now

      # start the machinery
      query = start_query(sobject, soql, options)
      results = nil

      loop do
        # check the status
        status = query.check_status

        # if finished get the result and we're done
        if status[:finished]

          # get the results and we're done
          results = query.get_results(:directory_path => options[:directory_path])
          @logger.info "Query finished. Results: #{results_to_string(results)}" if @logger
          break
        end

        # if we've run out of time limit, go away
        if Time.now - start_time > time_limit
          @logger.warn "Ran out of time limit, downloading what's available and terminating" if @logger

          # download what's available
          results = query.get_results(
            :directory_path => options[:directory_path],
          )

          @logger.info "Downloaded the following files: #{results[:filenames]} The following didn't finish in time: #{results[:unfinished_subqueries]}. Results: #{results_to_string(results)}" if @logger
          break
        end

        # restart whatever needs to be restarted and sleep
        query.get_result_or_restart(:directory_path => options[:directory_path])
        @logger.info "Sleeping #{check_interval}" if @logger
        sleep(check_interval)
      end

      return results
    end

    def query_fields(sobject,options ={})
      check_interval = options[:check_interval] || CHECK_INTERVAL
      time_limit = options[:time_limit] || QUERY_TIME_LIMIT

      start_time = Time.now
      # start the machinery
      query = SalesforceBulkQuery::Query.new(sobject, nil, @connection, {:logger => @logger}.merge(options))
      query.start_with_fields

      results = nil
      loop do

        # check the status
        status = query.check_status

        # if finished get the result and we're done
        if status[:finished]

          # get the results and we're done
          results = query.get_results(:directory_path => options[:directory_path])
          @logger.info "Query finished. Results: #{results_to_string(results)}" if @logger
          break
        end

        # if we've run out of time limit, go away
        if Time.now - start_time > time_limit
          @logger.warn "Ran out of time limit, downloading what's available and terminating" if @logger

          # download what's available
          results = query.get_results(
              :directory_path => options[:directory_path]
          )

          @logger.info "Downloaded the following files: #{results[:filenames]} The following didn't finish in time: #{results[:unfinished_subqueries]}. Results: #{results_to_string(results)}" if @logger
          break
        end

        # restart whatever needs to be restarted and sleep
        query.get_result_or_restart(:directory_path => options[:directory_path])
        @logger.info "Sleeping #{check_interval}" if @logger
        sleep(check_interval)
      end

      return results

    end


    # Start the query (synchronous method)
    # @params see #query
    # @return Query instance with the running query
    def start_query(sobject, soql, options={})
      # create the query, start it and return it
      query = SalesforceBulkQuery::Query.new(sobject, soql, @connection, {:logger => @logger}.merge(options))
      query.start
      return query
    end

    private
    # create a hash with just the fields we want to show in logs
    def results_to_string(results)
      return results.merge({
        :results => results[:results].map do |r|
          r.merge({
            :unfinished_batches => r[:unfinished_batches].map do |b|
              b.to_log
            end
          })
        end,
        :done_jobs => results[:done_jobs].map {|j| j.to_log}
      })
    end
  end
end