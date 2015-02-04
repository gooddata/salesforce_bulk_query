require 'spec_helper'
require 'multi_json'
require 'csv'
require 'tmpdir'
require 'logger'
require 'set'

# test co nejak nafakuje tu situaci v twc
describe SalesforceBulkQuery do
  before :all do
    WebMock.allow_net_connect!

    @client = SpecHelper.create_default_restforce
    @api = SpecHelper.create_default_api(@client)
    @entity = ENV['ENTITY'] || 'Opportunity'
    @field_list = (ENV['FIELD_LIST'] || "Id,CreatedDate").split(',')
    @api_version = SpecHelper.api_version
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
        # stub the timeout on query
        host = URI.parse(@api.instance_url).host
        query_url = "#{host}/services/data/v#{@api_version}/query"
        query_regexp = Regexp.new(query_url)
        # 4 timeouts (first get the oldest record), then fake a
        # 0 count query response
        stub_request(:get, query_regexp).to_timeout.times(4).then.to_return(
          :body => "{\"totalSize\":0,\"done\":true,\"records\":[]}",
          :headers => {
            "date"=>"Wed, 04 Feb 2015 01:18:45 GMT",
            "set-cookie"=>"BrowserId=hahaha;Path=/;Domain=.salesforce.com;Expires=never",
            "expires"=>"Thu, 01 Jan 1970 00:00:00 GMT",
            "sforce-limit-info"=>"api-usage=6666/15000",
            "content-type"=>"application/json;charset=UTF-8",
            "transfer-encoding"=>"chunked"}
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
        t = "2020-01-01"
        to = "#{t}T00:00:00.000Z"
        result = @api.query(
          "Account",
          "SELECT Id, Name, Industry, Type FROM Account",
          :check_interval => 30,
          :directory_path => tmp,
          :created_from => from,
          :created_to => to,
          :single_batch => true,
          :count_lines => true
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
