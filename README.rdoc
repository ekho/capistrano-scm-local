capistrano-scm-local [![Gem Version](https://badge.fury.io/rb/capistrano-scm-local.svg)](http://badge.fury.io/rb/capistrano-scm-local)
====================

allow deploy from local directory

Gemfile
```ruby
gem 'capistrano-scm-local', '~> 0.1', :github => 'ekho/capistrano-scm-local'
```
OR
```ruby
source 'https://rubygems.org'
gem 'capistrano-scm-local', '~> 0.1'
```

deploy.rb
```ruby
set :scm, :local
set :local_strategy, :archive
set :repo_url, 'path/to/source'
```

:local_strategy can be :default or :archive.
**:default** - directly uploads folder;
**:archive** - makes tar.gz, uploads it and unpack.