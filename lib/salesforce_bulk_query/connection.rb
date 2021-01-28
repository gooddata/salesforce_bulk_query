require 'xmlsimple'
require 'net/http'

module SalesforceBulkQuery

  # Connection to the Salesforce API
  # shared in all classes that do some requests
  class Connection
    def initialize(client, api_version, logger=nil, filename_prefix=nil, ssl_version = nil, force_encoding = false)
      @client = client
      @logger = logger
      @filename_prefix = filename_prefix
      @ssl_version = ssl_version
      @force_encoding = force_encoding


      @@API_VERSION = api_version
      @@PATH_PREFIX = "/services/async/#{@@API_VERSION}/"
    end

    attr_reader :client

    XML_REQUEST_HEADER = {'Content-Type' => 'application/xml; charset=utf-8'}
    CSV_REQUEST_HEADER = {'Content-Type' => 'text/csv; charset=UTF-8'}

    def session_header
      {'X-SFDC-Session' => @client.options[:oauth_token]}
    end

    def parse_xml(xml)
      parsed = nil
      begin
        parsed = XmlSimple.xml_in(xml)
      rescue => e
        @logger.error "Error parsing xml: #{xml}\n#{e}\n#{e.backtrace}"
        raise
      end

      return parsed
    end

    def post_xml(path, xml, options={})
      path = "#{@@PATH_PREFIX}#{path}"
      headers = options[:csv_content_type] ? CSV_REQUEST_HEADER : XML_REQUEST_HEADER

      response = nil
      # do the request
      with_retries do
        begin
          response = @client.post(path, xml, headers.merge(session_header))
        rescue JSON::ParserError => e
          if e.message.index('ExceededQuota')
            raise "You've run out of sfdc batch api quota. Original error: #{e}\n #{e.backtrace}"
          end
          raise e
        end
      end

      return parse_xml(response.body)
    end

    def get_xml(path, options={})
      path = "#{@@PATH_PREFIX}#{path}"
      headers = XML_REQUEST_HEADER

      response = nil
      with_retries do
        response = @client.get(path, {}, headers.merge(session_header))
      end

      return options[:skip_parsing] ? response.body : parse_xml(response.body)
    end

    def get_to_file(path, filename)
      path = "#{@@PATH_PREFIX}#{path}"
      uri = URI.parse( @client.options[:instance_url])
      # open a file
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ssl_version = @ssl_version if !@ssl_version.nil?

      # Default read timeout is 10 minutes
      http.read_timeout = 600

      headers = XML_REQUEST_HEADER.merge(session_header)
      @logger.info "Doing GET to #{path}, headers #{headers}" if @logger

      if @filename_prefix
        filename = "#{@filename_prefix}_#{filename}"
      end

      # do the request
      http.request_get(path, headers) do |res|

        @logger.info "Got response #{res.inspect}, reading response body by chunks and writing to #{filename}" if @logger

        File.open(filename, 'w') do |file|
          # write the body to the file by chunks
          res.read_body do |segment|
            if (@force_encoding)
              file.write(segment.force_encoding('UTF-8'))
            else
              file.write(segment.encode('UTF-8', :invalid => :replace, :undef => :replace,:replace => "?"))
            end
          end
        end
      end
    end

    def with_retries
      i = 0
      begin
        yield
      rescue => e
        i += 1
        if i < 3
          @logger.warn "Retrying, got error: #{e}, #{e.backtrace}" if @logger
          retry
        else
          @logger.error "Failed 3 times, last error: #{e}, #{e.backtrace}" if @logger
          raise
        end
      end
    end

    def query_count(sobject, date_field, from, to)
      # do it with retries, if it doesn't succeed, return nil, don't fail.
      soql = "SELECT COUNT() FROM #{sobject} WHERE #{date_field} >= #{from} AND #{date_field} < #{to}"
      begin
        with_retries do
          q = @client.query(soql)
          return q.size
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        @logger.warn "Timeout getting count: #{soql}. Error: #{e}. Taking it as failed verification" if @logger
        return nil
      end
    end

    def to_log
      return {
        :client => "Restforce asi",
        :filename_prefix => @filename_prefix,
        :api_version => @@API_VERSION,
        :path_prefix => @@PATH_PREFIX
      }
    end
  end
end
