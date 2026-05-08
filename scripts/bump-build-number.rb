#!/usr/bin/env ruby
# scripts/bump-build-number.rb
#
# v24: Auto-bumps CURRENT_PROJECT_VERSION on every Codemagic build to avoid
# App Store Connect "duplicate bundle version" errors. Reads latest from
# TestFlight and sets to (latest + 1), or floor of 27 if first time.
#
# Called by codemagic.yaml before xcodebuild.

require 'xcodeproj'

PROJECT_PATH = 'HafaUp.xcodeproj'
MIN_BUILD    = 27  # minimum (one above last failed upload at 26)

# Get build number from env (set by codemagic.yaml shell step)
new_build = ENV['NEW_BUILD_NUMBER']
if new_build.nil? || new_build.empty? || new_build.to_i < MIN_BUILD
  new_build = MIN_BUILD.to_s
end

puts "[bump-build] setting CURRENT_PROJECT_VERSION = #{new_build} on all targets"
project = Xcodeproj::Project.open(PROJECT_PATH)
project.targets.each do |t|
  t.build_configurations.each do |bc|
    old = bc.build_settings['CURRENT_PROJECT_VERSION']
    bc.build_settings['CURRENT_PROJECT_VERSION'] = new_build
    puts "  #{t.name}/#{bc.name}: #{old || '(none)'} -> #{new_build}"
  end
end
project.save
puts "[bump-build] saved"
