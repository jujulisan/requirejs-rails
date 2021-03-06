require "ostruct"
require "pathname"

require "requirejs/rails"

module Requirejs
  module Rails
    class Builder
      def initialize(config)
        @config = config
      end

      def build
        @config.tmp_dir
      end

      def generate_rjs_driver
        fork do
          templ = Thread.new { Erubis::Eruby.new(@config.driver_template_path.read) }.join.value
          Thread.new do
            @config.driver_path.open('w') do |f|
              f.write(templ.result(@config.get_binding))
            end
          end
        end
      end
    end
  end
end
