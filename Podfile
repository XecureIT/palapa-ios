project 'PALAPA.xcodeproj'
platform :ios, '10.0'
plugin 'cocoapods-binary'

use_frameworks!

###
# OWS Pods
###

pod 'SignalCoreKit', git: 'https://github.com/signalapp/SignalCoreKit.git', testspecs: ["Tests"]
# pod 'SignalCoreKit', path: '../SignalCoreKit', testspecs: ["Tests"]

pod 'AxolotlKit', git: 'https://github.com/signalapp/SignalProtocolKit.git', branch: 'master', testspecs: ["Tests"]
# pod 'AxolotlKit', path: '../SignalProtocolKit', testspecs: ["Tests"]

pod 'HKDFKit', git: 'https://github.com/signalapp/HKDFKit.git', testspecs: ["Tests"]
# pod 'HKDFKit', path: '../HKDFKit', testspecs: ["Tests"]

pod 'Curve25519Kit', git: 'https://github.com/signalapp/Curve25519Kit', testspecs: ["Tests"]
# pod 'Curve25519Kit', path: '../Curve25519Kit', testspecs: ["Tests"]

pod 'SignalMetadataKit', git: 'git@github.com:signalapp/SignalMetadataKit', testspecs: ["Tests"]
# pod 'SignalMetadataKit', path: '../SignalMetadataKit', testspecs: ["Tests"]

pod 'blurhash', git: 'https://github.com/signalapp/blurhash', branch: 'signal-master'

pod 'SignalServiceKit', path: '.', testspecs: ["Tests"]

# Project does not compile with PromiseKit 6.7.1
# see: https://github.com/mxcl/PromiseKit/issues/990
pod 'PromiseKit', "6.5.3"

# pod 'GRDB.swift/SQLCipher', path: '../GRDB.swift'
pod 'GRDB.swift/SQLCipher'

pod 'SQLCipher', ">= 4.0.1"

###
# forked third party pods
###

# Forked for performance optimizations that are not likely to be upstreamed as they are specific
# to our limited use of Mantle
pod 'Mantle', git: 'https://github.com/signalapp/Mantle', branch: 'signal-master'
# pod 'Mantle', path: '../Mantle'

# Forked for compatibily with the ShareExtension, changes have an open PR, but have not been merged.
pod 'YapDatabase/SQLCipher', :git => 'https://github.com/signalapp/YapDatabase.git', branch: 'signal-release'
# pod 'YapDatabase/SQLCipher', path: '../YapDatabase'

# Forked to incorporate our self-built binary artifact.
pod 'GRKOpenSSLFramework', git: 'https://github.com/signalapp/GRKOpenSSLFramework', branch: 'mkirk/1.0.2t'
#pod 'GRKOpenSSLFramework', path: '../GRKOpenSSLFramework'

pod 'Starscream', git: 'git@github.com:signalapp/Starscream.git', branch: 'signal-release'
# pod 'Starscream', path: '../Starscream'

###
# third party pods
####

pod 'AFNetworking/NSURLSession', inhibit_warnings: true
pod 'PureLayout', :inhibit_warnings => true
pod 'Reachability', :inhibit_warnings => true
pod 'lottie-ios', :inhibit_warnings => true
pod 'YYImage', :inhibit_warnings => true
pod 'ZXingObjC', git: 'https://github.com/TheLevelUp/ZXingObjC', :binary => true

target 'PALAPA' do
  # Pods only available inside the main Signal app
  pod 'SSZipArchive', :inhibit_warnings => true
  pod 'SignalRingRTC', path: 'ThirdParty/SignalRingRTC.podspec', inhibit_wranings: true

  target 'PALAPATests' do
    inherit! :search_paths
  end

  target 'PALAPAPerformanceTests' do
    inherit! :search_paths
  end
end

# These extensions inherit all of the pods
target 'SignalShareExtension'
target 'SignalMessaging'

post_install do |installer|
  enable_extension_support_for_purelayout(installer)
  configure_warning_flags(installer)
  configure_testable_build(installer)
  disable_bitcode(installer)
end

# PureLayout by default makes use of UIApplication, and must be configured to be built for an extension.
def enable_extension_support_for_purelayout(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "PureLayout"
      target.build_configurations.each do |build_configuration|
        if build_configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] == 'YES'
          build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = ['$(inherited)', 'PURELAYOUT_APP_EXTENSIONS=1']
        end
      end
    end
  end
end

# We want some warning to be treated as errors.
#
# NOTE: We have to manually keep this list in sync with what's in our
# Signal.xcodeproj config in Xcode go to:
#   Signal Project > Build Settings > Other Warning Flags
def configure_warning_flags(installer)
  installer.pods_project.targets.each do |target|
      target.build_configurations.each do |build_configuration|
          build_configuration.build_settings['WARNING_CFLAGS'] = ['$(inherited)',
                                                                  '-Werror=incompatible-pointer-types',
                                                                  '-Werror=protocol',
                                                                  '-Werror=incomplete-implementation',
                                                                  '-Werror=objc-literal-conversion']
      end
  end
end

def configure_testable_build(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_configuration|
      next unless ["Testable Release", "Debug"].include?(build_configuration.name)

      build_configuration.build_settings['OTHER_CFLAGS'] ||= '$(inherited) -DTESTABLE_BUILD'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] ||= '$(inherited) -DTESTABLE_BUILD'
      build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= '$(inherited) TESTABLE_BUILD=1'
      build_configuration.build_settings['ENABLE_TESTABILITY'] = 'YES'
      build_configuration.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
    end
  end
end


def disable_bitcode(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
