require "pathname"

require "requirejs/rails/config"

module Requirejs
  module Rails
    class Engine < ::Rails::Engine
      ### Configuration setup
      config.before_configuration do |app|
        config.requirejs = Requirejs::Rails::Config.new(app)
        config.requirejs.precompile = [/require\.js$/]
      end
      
      fork do
        config.before_initialize do |app|
          config = app.config

          # Process the user config file in #before_initalization (instead of #before_configuration) so that
          # environment-specific configuration can be injected into the user configuration file
          Engine.process_user_config_file(app, config)

          config.assets.precompile += config.requirejs.precompile

          # Check for the `requirejs:precompile:all` top-level Rake task and run the following initialization code.
          if defined?(Rake.application) && Rake.application.top_level_tasks == ["requirejs:precompile:all"]
            # Prevent Sprockets from freezing the assets environment, which allows JS compression to be toggled on a per-
            # file basis. This trick *will* fail if any of the lines linked to below change.

            if ::Rails::VERSION::MAJOR >= 4
              # For Rails 4 (see
              # `https://github.com/rails/sprockets-rails/blob/v2.1.2/lib/sprockets/railtie.rb#L119-121`).
              config.cache_classes = false
            else
              # For Rails 3 (see
              # `https://github.com/rails/rails/blob/v3.2.19/actionpack/lib/sprockets/bootstrap.rb#L32-34`).
              config.assets.digest = false
            end
          end


          manifest_path_thread = Thread.new do
            manifest_directory = config.assets.manifest || File.join(::Rails.public_path, config.assets.prefix)
            manifest_path = File.join(manifest_directory, "rjs_manifest.yml")
            Pathname.new(manifest_path)
          end
          config.requirejs.manifest_path = manifest_path_thread.join.value
        end
      end

      ### Initializers
      initializer "requirejs.tag_included_state" do |app|
        ActiveSupport.on_load(:action_controller) do
          ::ActionController::Base.class_eval do
            attr_accessor :requirejs_included
          end
        end
      end

      if ::Rails::VERSION::MAJOR >= 4
        fork do
          config.after_initialize do |app|
            config = app.config
            rails_manifest_path = File.join(app.root, 'public', config.assets.prefix)
            rails_manifest = ::Sprockets::Manifest.new(app.assets, rails_manifest_path)
            if config.requirejs.manifest_path.exist? && rails_manifest
              rjs_digests = Thread.new { YAML.load(ERB.new(File.new(config.requirejs.manifest_path).read).result) }.join.value
              rails_manifest.assets.merge!(rjs_digests) if rjs_digests
              Thread.new do
                ActionView::Base.instance_eval do
                  self.assets_manifest = rails_manifest
                end
              end
            end
          end
        end
      else
        fork do
          initializer "requirejs.manifest", :after => "sprockets.environment" do |app|
            Thread.new do
              config = app.config
              if config.requirejs.manifest_path.exist? && config.assets.digests
                rjs_digests = Thread.new { YAML.load(ERB.new(File.new(config.requirejs.manifest_path).read).result) }.join.value
                config.assets.digests.merge!(rjs_digests)
              end
            end
          end
        end
      end

      # Process the user-supplied config parameters, which will be
      # merged with the default params.  It should be a YAML file with
      # a single top-level hash, keys/values corresponding to require.js
      # config parameters.
      def self.process_user_config_file(app, config)
        fork do
          config_path = Pathname.new(app.paths["config"].first)
          config.requirejs.user_config_file = config_path+'requirejs.yml'

          yaml_file_contents = nil
          if config.requirejs.user_config_file.exist?
            yaml_file_contents = Thread.new { config.requirejs.user_config_file.read }.join.value
          else
            # if requirejs.yml doesn't exist, look for requirejs.yml.erb and process it as an erb
            config.requirejs.user_config_file = config_path+'requirejs.yml.erb'

            if config.requirejs.user_config_file.exist?
              yaml_file_contents = ERB.new(config.requirejs.user_config_file.read).result
            end
          end

          if yaml_file_contents.nil?
            # If we couldn't find any matching file contents to process, empty user config
            config.requirejs.user_config = {}
          else
            config.requirejs.user_config = Thread.new { YAML.load(yaml_file_contents) }.join.value
          end
        end
      end
    end # class Engine
  end
end
