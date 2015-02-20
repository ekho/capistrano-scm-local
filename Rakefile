# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://guides.rubygems.org/specification-reference/ for more options
  gem.name = "capistrano-scm-local"
  gem.homepage = "http://github.com/ekho/capistrano-scm-local"
  gem.license = "MIT"
  gem.summary = %Q{Capistrano SCM Local - Deploy from local copy}
  gem.description = %Q{Capistrano extension for deploying form local directory}
  gem.email = "ekho@ekho.name"
  gem.authors = ["Boris Gorbylev"]
  gem.require_paths = ["lib"]
  gem.add_dependency 'capistrano', '~> 3.1'
  gem.add_dependency 'minitar', '~> 0.5.4'
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

desc "Code coverage detail"
task :simplecov do
  ENV['COVERAGE'] = "true"
  Rake::Task['test'].execute
end

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "capistrano-scm-local #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end