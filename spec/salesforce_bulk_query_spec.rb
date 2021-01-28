require 'multi_json'
require 'csv'
require 'tmpdir'
require 'logger'
require 'set'
require 'salesforce_bulk_query'
require 'restforce'
require 'webmock/rspec'

class Helper
  DEFAULT_API_VERSION = '41.0'
  def self.create_default_restforce
    Restforce.new(
      :username => ENV['USERNAME'],
      :password => ENV['PASSWORD'],
      :security_token => ENV['TOKEN'],
      :client_id => ENV['CLIENT_ID'],
      :client_secret => ENV['CLIENT_SECRET'],
      :api_version => api_version
    )
  end

  def self.api_version
    ENV['API_VERSION'] || DEFAULT_API_VERSION
  end

  def self.create_default_api(restforce)
    # switch off the normal logging
    Restforce.log = false

    SalesforceBulkQuery::Api.new(restforce,
      :api_version => ENV['API_VERSION'] || DEFAULT_API_VERSION,
      :logger => ENV['LOGGING'] ? Logger.new(STDOUT): nil
    )
  end
end

# test co nejak nafakuje tu situaci v twc
describe SalesforceBulkQuery do
  before :all do
    WebMock.allow_net_connect!

    @client = Helper.create_default_restforce
    @api = Helper.create_default_api(@client)
    @entity = ENV['ENTITY'] || 'Opportunity'
    @field_list = (ENV['FIELD_LIST'] || "Id,CreatedDate").split(',')
    @api_version = Helper.api_version
  end

  describe "instance_url" do
    it "gives you some reasonable url" do
      url = @api.instance_url
      url.should_not be_empty
      url.should match(/salesforce\.com\//)
    end
  end

  describe "query" do
    context "if you give it an invalid SOQL" do
      it "fails with argument error" do
        expect{@api.query(@entity, "SELECT Id, SomethingInvalid FROM #{@entity}")}.to raise_error(ArgumentError)
      end
    end
    context "when you give it no options" do
      it "downloads the data to a few files", :constraint => 'slow'  do
        result = @api.query(@entity, "SELECT #{@field_list.join(', ')} FROM #{@entity}", :count_lines => true)
        filenames = result[:filenames]
        filenames.should have_at_least(2).items
        result[:jobs_done].should_not be_empty

        # no duplicate filenames
        expect(Set.new(filenames).length).to eq(filenames.length)

        filenames.each do |filename|
          File.size?(filename).should be_true

          lines = CSV.read(filename)

          if lines.length > 1
            # first line should be the header
            lines[0].should eql(@field_list)

            # first id shouldn't be emtpy
            lines[1][0].should_not be_empty
          end
        end
      end
    end
    context "when we want to mock things" do
      before(:each) do
        WebMock.allow_net_connect!
      end
      after(:each) do
        WebMock.allow_net_connect!
      end
      it "catches the timeout error for query" do
        host = URI.parse(@api.instance_url).host
        query_url = "#{host}/services/data/v#{@api_version}/query"
        # timeout fetching the oldest record, so it will use a default value
        stub_request(:get, Regexp.new(query_url))
          .with(query: { q: "SELECT CreatedDate FROM #{@entity} ORDER BY CreatedDate LIMIT 1" })
          .to_timeout
        # timeout on calls to count the number of entities, but eventually succeed
        stub_request(:get, Regexp.new(query_url))
          .with {|request|
            request.uri.query.start_with?("q=#{URI.encode("SELECT COUNT() FROM #{@entity} WHERE CreatedDate >= ")}")
          }.to_timeout.times(2).then.to_return(
            :body => "{\"totalSize\":0,\"done\":true,\"records\":[]}",
            :headers => {
              "date"=>"Wed, 04 Feb 2015 01:18:45 GMT",
              "set-cookie"=>"BrowserId=hahaha;Path=/;Domain=.salesforce.com;Expires=never",
              "expires"=>"Thu, 01 Jan 1970 00:00:00 GMT",
              "sforce-limit-info"=>"api-usage=6666/15000",
              "content-type"=>"application/json;charset=UTF-8",
              "transfer-encoding"=>"chunked"
            }
          )

        # do the actual request
        WebMock.allow_net_connect!
        result = @api.query(
          @entity,
          "SELECT #{@field_list.join(', ')} FROM #{@entity}",
          :count_lines => true,
          :single_batch => true
        )

        # check it
        expect(result[:succeeded]).to be_true
        expect(result[:unfinished_subqueries]).to be_empty
        expect(result[:filenames]).not_to be_empty
        expect(result[:jobs_done]).not_to be_empty
      end
    end
    context "when you give it all the options" do
      it "downloads a single file" do
        tmp = Dir.mktmpdir
        frm = "2000-01-01"
        from = "#{frm}T00:00:00.000Z"
        t = "3000-01-01"
        to = "#{t}T00:00:00.000Z"
        field = 'SystemModstamp'
        result = @api.query(
          "Account",
          "SELECT Id, Name, Industry, Type FROM Account",
          :check_interval => 30,
          :directory_path => tmp,
          :date_from => from,
          :date_to => to,
          :single_batch => true,
          :count_lines => true,
          :date_field => field
        )

        result[:filenames].should have(1).items
        result[:jobs_done].should_not be_empty

        filename = result[:filenames][0]

        File.size?(filename).should be_true
        lines = CSV.read(filename)

        # first line should be the header
        lines[0].should eql(["Id", "Name", "Industry", "Type"])

        # first id shouldn't be emtpy
        lines[1][0].should_not be_empty

        filename.should match(tmp)
        filename.should match(frm)
        filename.should match(t)
        filename.should match(field)
      end
    end
    context "when you give it a bad date_field" do
      it "fails with argument error with no from date" do
        expect{@api.query(@entity, "SELECT Id, CreatedDate FROM #{@entity}", :date_field => 'SomethingInvalid')}.to raise_error(ArgumentError)
      end
      it "fails with argument error with given from date" do
        from = "2000-01-01T00:00:00.000Z"
        expect{
          @api.query(
            @entity,
            "SELECT Id, CreatedDate FROM #{@entity}",
            :date_field => 'SomethingInvalid',
            :date_from => from
          )
        }.to raise_error(ArgumentError)
      end

    end
    context "when you give it a short time limit" do
      it "downloads some stuff is unfinished" do
        result = @api.query(
          "Opportunity",
          "SELECT Id, Name, CreatedDate FROM Opportunity",
          :time_limit => 15
        )
        # one of them should be non-empty
        expect((! result[:unfinished_subqueries].empty?) || (! result[:filenames].empty?)).to eq true
      end
    end
    context "when you pass a short job time limit" do
      it "creates quite a few jobs quickly", :skip => true do
        # development only
        result = @api.query(
          @entity,
          "SELECT Id, CreatedDate FROM #{@entity}",
          :count_lines => true,
          :job_time_limit => 60
        )
        require 'pry'; binding.pry
      end
    end
  end

  describe "start_query" do
    it "starts a query that finishes some time later" do
      query = @api.start_query("Opportunity",  "SELECT Id, Name, CreatedDate FROM Opportunity", :single_batch => true)

      # get a cofee
      sleep(60*2)

      # check the status
      result = query.get_available_results
      expect(result[:succeeded]).to eq true
      result[:filenames].should have_at_least(1).items
      result[:jobs_done].should_not be_empty
    end

  end
end
