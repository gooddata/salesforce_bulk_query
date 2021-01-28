# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib/", __FILE__)
require "salesforce_bulk_query/version"

Gem::Specification.new do |s|
  s.name = 'salesforce_bulk_query'
  s.version = SalesforceBulkQuery::VERSION
  s.authors = ['Petr Cvengros']
  s.email = ['petr.cvengros@gooddata.com']

  s.required_ruby_version = '>= 2.5'

  s.homepage = 'https://github.com/cvengros/salesforce_bulk_query'
  s.summary = %q{Downloading data from Salesforce Bulk API made easy and scalable.}
  s.description = %q{A library for downloading data from Salesforce Bulk API. We only focus on querying, other operations of the API aren't supported. Designed to handle a lot of data.}
  s.license = 'BSD'

  s.add_dependency 'json', '~> 2.0'
  s.add_dependency 'xml-simple', '~> 1.1'

  s.add_development_dependency 'multi_json', '~> 1.9'
  s.add_development_dependency 'restforce', '~> 5.0'
  s.add_development_dependency 'rspec', '~>2.14'
  s.add_development_dependency 'pry', '~>0.9'
  s.add_development_dependency 'pry-stack_explorer', '~>0.4' if RUBY_PLATFORM != 'java'
  s.add_development_dependency 'rake', '~> 10.3'
  s.add_development_dependency 'coveralls', '~> 0.7'
  s.add_development_dependency 'webmock', '~> 3.0'

  s.files = `git ls-files`.split($/)
  s.require_paths = ['lib']

  s.rubygems_version = "1.3.7"
end
