#!/usr/bin/env ruby
# scripts/setup-widget-target.rb
#
# v24: Adds HafaUpWidget Extension target to HafaUp.xcodeproj.
# Idempotent — safe to run on every build. Used by Codemagic so we don't
# need a Mac to set up the widget target via Xcode UI.
#
# Requires: gem install xcodeproj

require 'xcodeproj'

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

# 1. Create or fetch widget target
widget_target = project.targets.find { |t| t.name == WIDGET_NAME }
if widget_target.nil?
  puts "[setup-widget] creating widget target #{WIDGET_NAME}"
  widget_target = project.new_target(:app_extension, WIDGET_NAME, :ios, DEPLOYMENT_TGT)
else
  puts "[setup-widget] widget target already exists"
end

# 2. Build settings
widget_target.build_configurations.each do |bc|
  bc.build_settings['PRODUCT_BUNDLE_IDENTIFIER']  = WIDGET_BUNDLE
  bc.build_settings['DEVELOPMENT_TEAM']           = TEAM_ID
  bc.build_settings['CODE_SIGN_STYLE']            = 'Manual'
  bc.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TGT
  bc.build_settings['SWIFT_VERSION']              = '5.0'
  bc.build_settings['INFOPLIST_FILE']             = "#{WIDGET_NAME}/Info.plist"
  bc.build_settings['SKIP_INSTALL']               = 'YES'
  bc.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'NO'
  bc.build_settings['MARKETING_VERSION']          = '1.0'
  bc.build_settings['CURRENT_PROJECT_VERSION']    = '1'
  bc.build_settings['CODE_SIGN_IDENTITY']         = 'Apple Distribution'
end

# 3. Widget group
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

# 4. Shared ShipmentAttributes.swift in BOTH targets
hafaup_group = project.main_group.find_subpath(APP_TARGET_NAME, false)
if hafaup_group
  shared_ref = hafaup_group.files.find { |f| f.path == 'ShipmentAttributes.swift' }
  if shared_ref
    unless widget_target.source_build_phase.files_references.include?(shared_ref)
      widget_target.add_file_references([shared_ref])
      puts "[setup-widget] added shared ShipmentAttributes.swift to widget target"
    end
    unless app_target.source_build_phase.files_references.include?(shared_ref)
      app_target.add_file_references([shared_ref])
    end
  else
    puts "[setup-widget] creating reference for HafaUp/ShipmentAttributes.swift"
    if File.exist?('HafaUp/ShipmentAttributes.swift')
      shared_ref = hafaup_group.new_reference('ShipmentAttributes.swift')
      app_target.add_file_references([shared_ref])
      widget_target.add_file_references([shared_ref])
      puts "[setup-widget] linked shared file to both targets"
    end
  end
end

# 5. App-only new files
['ShipmentActivityManager.swift', 'LiveActivityBridge.swift'].each do |fname|
  full = "HafaUp/#{fname}"
  next unless File.exist?(full)
  ref = hafaup_group.files.find { |f| f.path == fname }
  unless ref
    ref = hafaup_group.new_reference(fname)
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

project.save
puts "[setup-widget] saved. DONE."
