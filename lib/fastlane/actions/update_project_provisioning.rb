module Fastlane
  module Actions
    module SharedValues

    end

    class UpdateProjectProvisioningAction < Action
      ROOT_CERTIFICATE_URL = "http://www.apple.com/appleca/AppleIncRootCertificate.cer"
      def self.run(params)

        # assign folder from parameter or search for xcodeproj file
        folder = params[:xcodeproj] || Dir["*.xcodeproj"].first
        
        # validate folder
        project_file_path = File.join(folder, "project.pbxproj")
        raise "Could not find path to project config '#{project_file_path}'. Pass the path to your project (not workspace)!".red unless File.exists?(project_file_path)

        # download certificate
        if not File.exists?(params[:certificate])
          Helper.log.info("Downloading root certificate from (#{ROOT_CERTIFICATE_URL}) to path '#{params[:certificate]}'")
          require 'open-uri'
          File.open(params[:certificate], "w") do |file|
            file.write(open(ROOT_CERTIFICATE_URL, "rb").read)
          end
        end

        # parsing mobileprovision file
        Helper.log.info("Parsing mobile provisioning profile from '#{params[:profile]}'")
        profile = File.read(params[:profile])
        p7 = OpenSSL::PKCS7.new(profile)
        store = OpenSSL::X509::Store.new
        raise "Could not find valid certificate at '#{params[:certificate]}'" unless (File.size(params[:certificate]) > 0)
        cert = OpenSSL::X509::Certificate.new(File.read(params[:certificate]))
        store.add_cert(cert)
        verification = p7.verify([cert], store)
        data = Plist::parse_xml(p7.data)
        
        target_filter = params[:target_filter]
        configuration = params[:build_configuration]

        # manipulate project file
        Helper.log.info("Going to update project '#{folder}' with UUID".green)
        require 'xcodeproj'

        project = Xcodeproj::Project.open(folder)
        project.targets.each do |target|

          if !target_filter || target.product_name.match(target_filter) || target.product_type.match(target_filter)
            Helper.log.info "Updating target #{target.product_name}...".green
          else
            Helper.log.info "Skipping target #{target.product_name} as it doesn't match the filter '#{target_filter}'".yellow
            next
          end

          target.build_configuration_list.build_configurations.each do |build_configuration|

            config_name = build_configuration.name
            if !configuration || config_name.match(configuration)
              Helper.log.info "Updating configuration #{config_name}...".green
            else
              Helper.log.info "Skipping configuration #{config_name} as it doesn't match the filter '#{configuration}'".yellow
              next
            end

            build_configuration.build_settings["PROVISIONING_PROFILE"] = data["UUID"]
          end
        end

        project.save

        # complete
        Helper.log.info("Successfully updated project settings in'#{params[:xcodeproj]}'".green)
      end

      def self.description
        "Update projects code signing settings from your profisioning profile"
      end

      def self.details
        [
          "This action retrieves a provisioning profile UUID from a provisioning profile (.mobileprovision) to set",
          "up the xcode projects' code signing settings in *.xcodeproj/project.pbxproj",
          "The `target_filter` value can be used to only update code signing for specified targets",
          "The `build_configuration` value can be used to only update code signing for specified build configurations of the targets passing through the `target_filter`",
          "Example Usage is the WatchKit Extension or WatchKit App, where you need separate provisioning profiles",
          "Example: `update_project_provisioning(xcodeproj: \"..\", target_filter: \".*WatchKit App.*\")"
          ].join("\n")
        end

        def self.available_options
          [
            FastlaneCore::ConfigItem.new(key: :xcodeproj,
             env_name: "FL_PROJECT_PROVISIONING_PROJECT_PATH",
             description: "Path to your Xcode project",
             optional: true,
             verify_block: Proc.new do |value|
              raise "Path to xcode project is invalid".red unless File.exists?(value)
            end),
            FastlaneCore::ConfigItem.new(key: :profile,
             env_name: "FL_PROJECT_PROVISIONING_PROFILE_FILE",
             description: "Path to provisioning profile (.mobileprovision)",
             default_value: Actions.lane_context[SharedValues::SIGH_PROFILE_PATH],
             verify_block: Proc.new do |value|
              raise "Path to provisioning profile is invalid".red unless File.exists?(value)
            end),
            FastlaneCore::ConfigItem.new(key: :target_filter,
             env_name: "FL_PROJECT_PROVISIONING_PROFILE_TARGET_FILTER",
             description: "A filter for the target name. Use a standard regex",
             optional: true),
            FastlaneCore::ConfigItem.new(key: :build_configuration,
             env_name: "FL_PROJECT_PROVISIONING_PROFILE_BUILD_CONFIGURATION",
             description: "A filter for the build configuration name. Use a standard regex. Applied to all configurations if not specified",
             optional: true),
            FastlaneCore::ConfigItem.new(key: :certificate,
             env_name: "FL_PROJECT_PROVISIONING_CERTIFICATE_PATH",
             description: "Path to apple root certificate",
             default_value: "/tmp/AppleIncRootCertificate.cer")
          ]
        end

        def self.authors
          ["tobiasstrebitzer", "czechboy0"]
        end

        def self.is_supported?(platform)
          [:ios, :mac].include?platform
        end
      end
    end
  end
