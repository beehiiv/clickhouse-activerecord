source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# json 3.0 dropped the second argument to JSON.parse, which ActiveSupport's JSON.decode still passes.
gem 'json', '< 3'

# Specify your gem's dependencies in clickhouse-activerecord.gemspec
gemspec
