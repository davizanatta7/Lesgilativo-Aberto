ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

if RUBY_VERSION == "3.3.0"
  $LOAD_PATH.unshift(File.expand_path("../lib/ruby330_patch", __dir__))
end

require "bootsnap/setup" # Speed up boot time by caching expensive operations.
