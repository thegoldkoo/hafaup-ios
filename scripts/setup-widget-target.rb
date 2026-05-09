#!/usr/bin/env ruby
# scripts/setup-widget-target.rb
#
# v24/v25: Adds HafaUpWidget Extension target to HafaUp.xcodeproj.
# Idempotent — safe to run on every build. Used by Codemagic so we don't
# need a Mac to set up the widget target via Xcode UI.
#
# v25 fixes (post external review):
#  - P1.1: don't assume PBXGroup named 'HafaUp' exists (files live at root
#    in this project). Discover the parent group from app target's source
#    build phase.
#  - P1.3: keep widget target's MARKETING_VERSION + CURRENT_PROJECT_VERSION
#    in lock-step with the app target. App Store rejects mismatched
#    versions for embedded extensions.

require 'xcodeproj'
require 'rexml/document'

PROJECT_PATH    = 'HafaUp.xcodeproj'
APP_TARGET_NAME = 'HafaUp'
WIDGET_NAME     = 'HafaUpWidget'
WIDGET_BUNDLE   = 'com.app.captainguam.HafaUpWidget'
APP_BUNDLE      = 'com.app.captainguam'
TEAM_ID         = 'GCFCJUMRPV'
DEPLOYMENT_TGT  = '16.1'

puts "[setup-widget] opening #{PROJECT_PATH}"
project = Xcodeproj::Project.open(PROJECT_PATH)

app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
raise "app target #{APP_TARGET_NAME} not found" unless app_target

def source_file_in_target?(target, filename)
  target.source_build_phase.files_references.any? do |ref|
    next false unless ref

    [ref.path, ref.name, ref.display_name].compact.any? do |value|
      path = value.to_s
      path == filename || path.end_with?("/#{filename}")
    end
  end
end

def ensure_scheme_builds_widget(widget_target)
  scheme_path = File.join('HafaUp.xcodeproj', 'xcshareddata', 'xcschemes', "#{APP_TARGET_NAME}.xcscheme")
  return unless File.exist?(scheme_path)

  doc = REXML::Document.new(File.read(scheme_path))
  entries = doc.elements['/Scheme/BuildAction/BuildActionEntries']
  return unless entries

  already_present = false
  entries.each_element('BuildActionEntry/BuildableReference') do |ref|
    if ref.attributes['BlueprintIdentifier'] == widget_target.uuid
      already_present = true
      break
    end
  end
  return if already_present

  entry = entries.add_element('BuildActionEntry', {
    'buildForTesting' => 'YES',
    'buildForRunning' => 'YES',
    'buildForProfiling' => 'YES',
    'buildForArchiving' => 'YES',
    'buildForAnalyzing' => 'YES'
  })
  entry.add_element('BuildableReference', {
    'BuildableIdentifier' => 'primary',
    'BlueprintIdentifier' => widget_target.uuid,
    'BuildableName' => "#{WIDGET_NAME}.appex",
    'BlueprintName' => WIDGET_NAME,
    'ReferencedContainer' => "container:#{PROJECT_PATH}"
  })

  formatter = REXML::Formatters::Pretty.new(3)
  formatter.compact = true
  File.open(scheme_path, 'w') do |file|
    file.write(%(<?xml version="1.0" encoding="UTF-8"?>\n))
    formatter.write(doc.root, file)
    file.write("\n")
  end
  puts "[setup-widget] added #{WIDGET_NAME} to #{scheme_path} build action"
end

# Discover the parent group of HafaUp source files.
# Project layout has files at main_group root with path = "HafaUp/X.swift"
# rather than under a 'HafaUp' PBXGroup. Find it by sampling an existing
# known file (ViewController.swift or AppDelegate.swift).
hafaup_group = nil
['ViewController.swift', 'AppDelegate.swift', 'WebView.swift'].each do |probe|
  ref = project.files.find do |f|
    p = f.path.to_s
    p == probe || p == "HafaUp/#{probe}" || p.end_with?("/#{probe}")
  end
  if ref
    hafaup_group = ref.parent
    puts "[setup-widget] resolved hafaup_group via #{probe}: #{hafaup_group.display_name.inspect}"
    break
  end
end
raise "could not resolve HafaUp parent group" unless hafaup_group

# Determine the path prefix used by existing files (e.g. "HafaUp/X.swift" vs "X.swift")
existing_paths = app_target.source_build_phase.files.map { |bf| bf.file_ref.path.to_s }
uses_prefix = existing_paths.any? { |p| p.start_with?("HafaUp/") }
prefix = uses_prefix ? "#{APP_TARGET_NAME}/" : ""
puts "[setup-widget] file path prefix in app target = #{prefix.inspect}"

# Borrow MARKETING_VERSION and CURRENT_PROJECT_VERSION from app target
app_marketing = app_target.build_configurations.first.build_settings['MARKETING_VERSION'] || '1.0'
app_build     = app_target.build_configurations.first.build_settings['CURRENT_PROJECT_VERSION'] || '1'
puts "[setup-widget] app version=#{app_marketing} build=#{app_build}"

# 1. Create or fetch widget target
widget_target = project.targets.find { |t| t.name == WIDGET_NAME }
if widget_target.nil?
  puts "[setup-widget] creating widget target #{WIDGET_NAME}"
  widget_target = project.new_target(
    :app_extension,
    WIDGET_NAME,
    :ios,
    DEPLOYMENT_TGT,
    project.products_group,
    :swift,
    WIDGET_NAME
  )
else
  puts "[setup-widget] widget target already exists"
end

# Xcode 26 archives this target as ".appex" if product metadata is left blank.
# Make the product identity concrete before xcodebuild resolves outputs.
widget_target.product_name = WIDGET_NAME if widget_target.respond_to?(:product_name=)
widget_target.product_type = 'com.apple.product-type.app-extension'
if widget_target.product_reference
  widget_target.product_reference.name = "#{WIDGET_NAME}.appex"
  widget_target.product_reference.path = "#{WIDGET_NAME}.appex"
  widget_target.product_reference.explicit_file_type = 'wrapper.app-extension'
  widget_target.product_reference.include_in_index = 0
end

# 2. Build settings — versions must MATCH app target
widget_target.build_configurations.each do |bc|
  bc.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  bc.build_settings['PRODUCT_NAME']               = WIDGET_NAME
  bc.build_settings['EXECUTABLE_NAME']            = '$(PRODUCT_NAME)'
  bc.build_settings['WRAPPER_EXTENSION']          = 'appex'
  bc.build_settings['WRAPPER_NAME']               = '$(PRODUCT_NAME).$(WRAPPER_EXTENSION)'
  bc.build_settings['FULL_PRODUCT_NAME']          = '$(WRAPPER_NAME)'
  bc.build_settings['CONTENTS_FOLDER_PATH']       = '$(WRAPPER_NAME)'
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER']  = WIDGET_BUNDLE
  bc.build_settings['DEVELOPMENT_TEAM']           = TEAM_ID
  bc.build_settings['CODE_SIGN_STYLE']            = 'Manual'
  bc.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TGT
  bc.build_settings['SWIFT_VERSION']              = '5.0'
  bc.build_settings['INFOPLIST_FILE']             = "#{WIDGET_NAME}/Info.plist"
  bc.build_settings['SKIP_INSTALL']               = 'YES'
  bc.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'NO'
  # P1.3: match app target versions so App Store doesn't reject the embedded extension
  bc.build_settings['MARKETING_VERSION']          = app_marketing
  bc.build_settings['CURRENT_PROJECT_VERSION']    = app_build
  bc.build_settings['CODE_SIGN_IDENTITY']         = 'Apple Distribution'
end

# 3. Widget group (under main_group, mirrors app structure)
widget_group = project.main_group.find_subpath(WIDGET_NAME, true)
widget_group.set_source_tree('SOURCE_ROOT')
widget_group.set_path(WIDGET_NAME)

['HafaUpWidgetBundle.swift', 'ShipmentLiveActivity.swift'].each do |fname|
  full_path = "#{WIDGET_NAME}/#{fname}"
  raise "missing #{full_path}" unless File.exist?(full_path)
  existing = widget_group.files.find { |f| f.path == fname }
  file_ref = existing || widget_group.new_reference(fname)
  unless widget_target.source_build_phase.files_references.include?(file_ref)
    widget_target.add_file_references([file_ref])
    puts "[setup-widget] added #{fname} to widget target"
  end
end

unless widget_group.files.find { |f| f.path == 'Info.plist' }
  widget_group.new_reference('Info.plist')
end

# 4. Shared ShipmentAttributes.swift in BOTH targets — use prefix-aware path
shared_name  = 'ShipmentAttributes.swift'
shared_disk  = "HafaUp/#{shared_name}"
shared_pbx   = "#{prefix}#{shared_name}"  # path the project uses

shared_ref = project.files.find { |f| f.path.to_s == shared_pbx || f.path.to_s.end_with?("/#{shared_name}") }
unless shared_ref
  if File.exist?(shared_disk)
    shared_ref = hafaup_group.new_reference(shared_pbx)
    shared_ref.source_tree = 'SOURCE_ROOT'
    puts "[setup-widget] created reference for #{shared_pbx}"
  else
    puts "[setup-widget] WARN: #{shared_disk} missing — skipping shared file step"
  end
end
if shared_ref
  unless app_target.source_build_phase.files_references.include?(shared_ref)
    app_target.add_file_references([shared_ref])
    puts "[setup-widget] added shared #{shared_name} to app target"
  end
  unless widget_target.source_build_phase.files_references.include?(shared_ref)
    widget_target.add_file_references([shared_ref])
    puts "[setup-widget] added shared #{shared_name} to widget target"
  end
end

# 5. App-only new files
['ShipmentActivityManager.swift', 'LiveActivityBridge.swift'].each do |fname|
  disk = "HafaUp/#{fname}"
  next unless File.exist?(disk)
  pbx = "#{prefix}#{fname}"
  ref = project.files.find { |f| f.path.to_s == pbx || f.path.to_s.end_with?("/#{fname}") }
  unless ref
    ref = hafaup_group.new_reference(pbx)
    ref.source_tree = 'SOURCE_ROOT'
    puts "[setup-widget] created reference for #{pbx}"
  end
  unless app_target.source_build_phase.files_references.include?(ref)
    app_target.add_file_references([ref])
    puts "[setup-widget] added #{fname} to app target"
  end
end

# 6. Embed widget extension
embed_phase = app_target.copy_files_build_phases.find { |p| ['Embed App Extensions', 'Embed Foundation Extensions'].include?(p.name) }
if embed_phase.nil?
  embed_phase = app_target.new_copy_files_build_phase('Embed App Extensions')
  embed_phase.symbol_dst_subfolder_spec = :plug_ins
  puts "[setup-widget] created Embed App Extensions phase"
end
widget_product = widget_target.product_reference
unless embed_phase.files_references.include?(widget_product)
  bf = embed_phase.add_file_reference(widget_product)
  bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  puts "[setup-widget] embedded widget"
end

# 7. App depends on widget
unless app_target.dependencies.any? { |d| d.target == widget_target }
  app_target.add_dependency(widget_target)
  puts "[setup-widget] app depends on widget"
end

ensure_scheme_builds_widget(widget_target)

required_app_sources = [
  'ShipmentAttributes.swift',
  'ShipmentActivityManager.swift',
  'LiveActivityBridge.swift'
]
missing_app_sources = required_app_sources.reject { |fname| source_file_in_target?(app_target, fname) }
unless missing_app_sources.empty?
  raise "[setup-widget] app target missing sources: #{missing_app_sources.join(', ')}"
end
puts "[setup-widget] verified app target live activity sources"

required_widget_sources = [
  'ShipmentAttributes.swift',
  'HafaUpWidgetBundle.swift',
  'ShipmentLiveActivity.swift'
]
missing_widget_sources = required_widget_sources.reject { |fname| source_file_in_target?(widget_target, fname) }
unless missing_widget_sources.empty?
  raise "[setup-widget] widget target missing sources: #{missing_widget_sources.join(', ')}"
end
puts "[setup-widget] verified widget target live activity sources"

unless widget_target.product_reference && widget_target.product_reference.path == "#{WIDGET_NAME}.appex"
  raise "[setup-widget] widget product is not #{WIDGET_NAME}.appex"
end

unless embed_phase.files_references.include?(widget_target.product_reference)
  raise "[setup-widget] app target is not embedding #{WIDGET_NAME}.appex"
end
puts "[setup-widget] verified #{WIDGET_NAME}.appex is embedded"

project.save
puts "[setup-widget] saved. DONE."
