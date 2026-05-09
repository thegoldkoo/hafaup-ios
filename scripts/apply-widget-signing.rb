#!/usr/bin/env ruby
# scripts/apply-widget-signing.rb
#
# v25: Belt-and-suspenders for widget extension code signing in Codemagic CI.
#
# The pipeline runs:
#   1. setup-widget-target.rb            (creates HafaUpWidget target if missing)
#   2. fetch-signing-files com.app.captainguam.HafaUpWidget --create
#   3. xcode-project use-profiles --project HafaUp.xcodeproj
#   4. <this script>                     ← verifies widget target signing settings
#   5. xcodebuild archive
#
# Why this script: `xcode-project use-profiles` auto-detects profiles by
# PRODUCT_BUNDLE_IDENTIFIER, but for newly-added targets it sometimes misses
# PROVISIONING_PROFILE_SPECIFIER or CODE_SIGN_IDENTITY. Without those set,
# archive fails with "No profile for team... matching" or signs ad-hoc.
#
# This script:
#   - Locates the provisioning profile file matching the widget bundle id
#   - Reads its UUID + Name from the .mobileprovision plist
#   - Sets PROVISIONING_PROFILE_SPECIFIER + CODE_SIGN_IDENTITY explicitly
#     on every build configuration of the widget target
#   - Idempotent — re-running has no effect if already correct.

require 'xcodeproj'

PROJECT_PATH    = 'HafaUp.xcodeproj'
WIDGET_NAME     = 'HafaUpWidget'
WIDGET_BUNDLE   = 'com.app.captainguam.HafaUpWidget'
TEAM_ID         = 'GCFCJUMRPV'

# Codemagic stores fetched profiles here on the build VM
PROFILE_DIRS = [
  ENV['CM_PROFILES'],
  File.expand_path('~/Library/MobileDevice/Provisioning Profiles'),
  ENV['XCODE_PROVISIONING_PROFILES'],
  '/tmp/build/profiles'
].compact

PROFILE_ROOTS = [
  ENV['CM_BUILD_DIR'],
  ENV['HOME'],
  Dir.pwd,
  '/tmp'
].compact.uniq

def parse_profile(path)
  # .mobileprovision is a CMS-signed plist. Strip the signature to get the plist XML.
  raw = File.binread(path)
  start_idx = raw.index('<?xml')
  end_idx = raw.index('</plist>')
  return nil unless start_idx && end_idx
  xml = raw[start_idx..end_idx + '</plist>'.length - 1]
  require 'cfpropertylist'
  plist = CFPropertyList::List.new(data: xml).value
  plist = CFPropertyList.native_types(plist)
  plist
rescue LoadError
  # cfpropertylist unavailable — parse manually with regex (fragile but works for these fields)
  raw = File.binread(path)
  uuid = raw.match(/<key>UUID<\/key>\s*<string>([^<]+)<\/string>/)&.[](1)
  name = raw.match(/<key>Name<\/key>\s*<string>([^<]+)<\/string>/)&.[](1)
  app_id = raw.match(/<key>application-identifier<\/key>\s*<string>([^<]+)<\/string>/)&.[](1)
  team = raw.match(/<key>TeamIdentifier<\/key>\s*<array>\s*<string>([^<]+)<\/string>/)&.[](1)
  { 'UUID' => uuid, 'Name' => name, 'application-identifier' => app_id, 'TeamIdentifier' => [team] }
end

def bundle_id_from_application_identifier(app_id)
  app_id.to_s.split('.', 2)[1].to_s
end

def profile_match_kind(app_id, bundle_id)
  profile_bundle = bundle_id_from_application_identifier(app_id)
  return :exact if profile_bundle == bundle_id

  if profile_bundle.end_with?('.*')
    wildcard_prefix = profile_bundle[0...-1]
    return :wildcard if bundle_id.start_with?(wildcard_prefix)
  end

  nil
end

def find_widget_profile
  profile_paths = []

  PROFILE_DIRS.each do |dir|
    next unless dir && Dir.exist?(dir)

    profile_paths.concat(Dir.glob(File.join(dir, '*.mobileprovision')))
  end

  PROFILE_ROOTS.each do |root|
    next unless root && Dir.exist?(root)

    profile_paths.concat(Dir.glob(File.join(root, '**', '*.mobileprovision')))
  end

  profile_paths = profile_paths.uniq
  puts "[apply-widget-signing] scanned #{profile_paths.length} mobileprovision file(s)"

  matches = []

  profile_paths.each do |path|
    info = parse_profile(path)
    next unless info

    app_id = info.dig('Entitlements', 'application-identifier').to_s
    app_id = info['application-identifier'].to_s if app_id.empty?
    bundle_id = bundle_id_from_application_identifier(app_id)
    match_kind = profile_match_kind(app_id, WIDGET_BUNDLE)
    puts "  profile candidate: #{File.basename(path)} bundle=#{bundle_id} match=#{match_kind || 'no'} name=#{info['Name']}"
    if match_kind
      matches << { path: path, name: info['Name'], uuid: info['UUID'], kind: match_kind }
    end
  end

  matches.find { |candidate| candidate[:kind] == :exact } || matches.first
end

puts "[apply-widget-signing] looking for profile matching #{WIDGET_BUNDLE}"
profile = find_widget_profile

project = Xcodeproj::Project.open(PROJECT_PATH)
widget = project.targets.find { |t| t.name == WIDGET_NAME }
if widget.nil?
  puts "[apply-widget-signing] WARN: widget target not found — setup-widget-target.rb must run first"
  exit 0
end

if profile.nil?
  warn "[apply-widget-signing] ERROR: no .mobileprovision found for #{WIDGET_BUNDLE}"
  warn "                              The widget extension must have its own App Store provisioning profile."
  warn "                              Check the fetch-signing-files step and Apple Developer bundle id."
  widget.build_configurations.each do |bc|
    puts "  #{widget.name}/#{bc.name}: profile_specifier=#{bc.build_settings['PROVISIONING_PROFILE_SPECIFIER'].inspect} profile=#{bc.build_settings['PROVISIONING_PROFILE'].inspect}"
  end
  exit 1
else
  puts "[apply-widget-signing] found #{profile[:kind]} profile: #{profile[:name]} (UUID #{profile[:uuid]})"
  widget.build_configurations.each do |bc|
    bc.build_settings['CODE_SIGN_STYLE']                = 'Manual'
    bc.build_settings['CODE_SIGN_IDENTITY']             = 'Apple Distribution'
    bc.build_settings['DEVELOPMENT_TEAM']               = TEAM_ID
    bc.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = profile[:name]
    bc.build_settings['PROVISIONING_PROFILE']           = profile[:uuid]
    bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER']      = WIDGET_BUNDLE
    bc.build_settings.delete('PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]')
    bc.build_settings.delete('PROVISIONING_PROFILE[sdk=iphoneos*]')
    puts "  #{widget.name}/#{bc.name}: profile = #{profile[:name]}"
  end
end

project.save
puts "[apply-widget-signing] saved"
