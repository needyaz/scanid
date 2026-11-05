#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint scanid.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'scanid'
  s.version          = '0.1.0'
  s.summary          = 'Free, open-source on-device OCR, barcode, and document-edge detection, plus AAMVA/MRZ decoders.'
  s.description      = <<-DESC
Free, open-source on-device OCR, barcode scanning, and document-edge detection, plus AAMVA driver's-license and ICAO MRZ decoders. No server calls, no license fee.
                       DESC
  s.homepage         = 'https://github.com/needyaz/scanid'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Nate Eide' => 'nate@eide.us' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks = 'Vision'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
