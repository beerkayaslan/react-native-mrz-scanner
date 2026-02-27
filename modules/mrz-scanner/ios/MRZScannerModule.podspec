require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'MRZScannerModule'
  s.version        = package['version']
  s.summary        = 'Expo native module for iOS MRZ scanning via Vision'
  s.description    = 'Presents a native camera scanner and returns MRZ raw text'
  s.homepage       = 'https://github.com/hllibrhm01/DocumentAccept'
  s.license        = 'MIT'
  s.author         = 'hllibrhm01'
  s.source         = { :git => 'https://github.com/hllibrhm01/DocumentAccept.git', :tag => s.version.to_s }
  s.platforms      = { ios: '15.1' }

  s.swift_version  = '5.9'
  s.source_files   = '**/*.swift'

  s.dependency 'ExpoModulesCore'
end
