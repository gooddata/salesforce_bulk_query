require 'csv'

require 'salesforce_bulk_query/connection'
require 'salesforce_bulk_query/query'
require 'salesforce_bulk_query/logger'
require 'salesforce_bulk_query/utils'
require 'salesforce_bulk_query/version'


# Module where all the stuff is happening
module SalesforceBulkQuery

  # Abstracts the whole library, class the user interacts with
  class Api
    @@DEFAULT_API_VERSION = '29.0'

    Encoding.default_external = Encoding::UTF_8
    Encoding.default_internal = Encoding::UTF_8

    # Constructor
    # @param client [Restforce] An instance of the Restforce client, that is used internally to access Salesforce api
    # @param options
    def initialize(client, options={})
      @logger = options[:logger]

      api_version = options[:api_version] || @@DEFAULT_API_VERSION
      ssl_version = options[:ssl_version]
      # use our own logging middleware if logger passed
      if @logger && client.respond_to?(:middleware)
        client.middleware.use(SalesforceBulkQuery::Logger, @logger, options)
      end

      # initialize connection
      @connection = SalesforceBulkQuery::Connection.new(client, api_version, @logger, options[:filename_prefix], ssl_version, options[:force_encoding])
    end

    # Get the Salesforce instance URL
    def instance_url
      # make sure it ends with /
      url = @connection.client.instance_url
      url += '/' if url[-1] != '/'
      return url
    end

    CHECK_INTERVAL = 30

    # Query the Salesforce API. It's a blocking method - waits until the query is resolved
    # can take quite some time
    # @param sobject Salesforce object, e.g. "Opportunity"
    # @param soql SOQL query, e.g. "SELECT Name FROM Opportunity"
    # @return hash with :filenames and other useful stuff
    def query(sobject, soql, options={})
      @logger.info "Running query: #{soql}. Gem version salesforce_bulk_query: #{SalesforceBulkQuery::VERSION}" if @logger
      check_interval = options[:check_interval] || CHECK_INTERVAL
      time_limit = options[:time_limit] # in seconds

      start_time = Time.now

      # start the machinery
      query = start_query(sobject, soql, options)
      results = nil

      loop do
        # get available results and check the status
        results = query.get_available_results(options)
        @logger.debug "get_available_results: #{results}"

        # if finished get the result and we're done
        if results[:succeeded]

          # we're done
          @logger.info "Query succeeded. Results: #{results}" if @logger
          break
        end

        # if we've run out of time limit, go away
        if time_limit && (Time.now - start_time > time_limit)
          @logger.warn "Ran out of time limit, downloading what's available and terminating" if @logger

          @logger.info "Downloaded the following files: #{results[:filenames]} The following didn't finish in time: #{results[:unfinished_subqueries]}." if @logger
          break
        end

        @logger.info "Sleeping #{check_interval}" if @logger
        @logger.info "Downloaded files: #{results[:filenames].length} Jobs in progress: #{query.jobs_in_progress.length}"
        sleep(check_interval)
      end

      # nice list of files to log
      if @logger && ! results[:filenames].empty?

        @logger.info "Download finished. Downloaded files in #{File.dirname(results[:filenames][0])}. Filename size [line count]:"
        @logger.info "\n" + results[:filenames].sort.map{|f| "#{File.basename(f)} #{File.size(f)} #{Utils.line_count(f) if options[:count_lines]}"}.join("\n")
      end
      return results
    end

    # Start the query (synchronous method)
    # @params see #query
    # @return Query instance with the running query
    def start_query(sobject, soql, options={})
      # create the query, start it and return it
      query = SalesforceBulkQuery::Query.new(sobject, soql, @connection, {:logger => @logger}.merge(options))
      query.start(options)
      return query
    end
  end
end
