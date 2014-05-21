# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib/", __FILE__)
require "salesforce_bulk_query/version"

Gem::Specification.new do |s|
  s.name = 'salesforce_bulk_query'
  s.version = SalesforceBulkQuery::VERSION
  s.authors = ['Petr Cvengros']
  s.email = ['petr.cvengros@gooddata.com']

  s.required_ruby_version = '~> 1.9'

  s.homepage = 'https://github.com/cvengros/salesforce_bulk_query'
  s.summary = %q{Ruby wrapper over the Salesforce Bulk Query API}
  s.description = %q{It's awesome}

  s.add_dependency 'json'
  s.add_dependency 'xml-simple'

  s.add_development_dependency 'multi_json'
  s.add_development_dependency 'restforce'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'pry'


  s.files = `git ls-files`.split($/)
  s.require_paths = ['lib']

  s.rubygems_version = "1.3.7"
end
