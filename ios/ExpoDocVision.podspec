Pod::Spec.new do |s|
  s.name           = 'ExpoDocVision'
  s.version        = '0.1.0'
  s.summary        = 'Expo native module for offline document OCR on iOS using Apple Vision & PDFKit'
  s.description    = <<-DESC
    expo-doc-vision is an Expo native module that provides offline document OCR
    capabilities on iOS using Apple Vision and PDFKit. It supports both images
    (JPG, PNG, HEIC) and PDF documents (text-based and scanned).
  DESC
  s.author         = 'zhanziyang'
  s.homepage       = 'https://github.com/zhanziyang/expo-doc-vision'
  s.license        = 'MIT'
  s.platforms      = { :ios => '13.0' }
  s.source         = { :git => 'https://github.com/zhanziyang/expo-doc-vision.git', :tag => "v#{s.version}" }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = '**/*.swift'
  s.frameworks = 'Vision', 'PDFKit', 'UIKit', 'CoreGraphics'

  s.swift_version = '5.4'
end
