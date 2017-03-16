module Marmara
  module Config
    attr_accessor :options

    def output_directory
      @output_directory || (options || {output_directory: 'log/css'})[:output_directory]
    end

    def output_directory=(dir)
      @output_directory = dir
    end

    def logger=(logger)
      @logger = logger
    end

    def log(str, method = :info)
      if @logger
        @logger.send(method, str)
      elsif @logger.nil?
        puts str
      end
    end

    def ignore?(file)
      return false unless options

      [*options[:ignore]].each do |matcher|
        if matcher.is_a?(Regexp)
          return true if file =~ matcher
        else
          return true if file.start_with?(matcher)
        end
      end

      return false
    end

    def get_report_filename(uri)
      if options
        [*options[:rewrite]].each do |rule|
          return uri.gsub(rule[:from], rule[:to]) if uri =~ rule[:from]
        end
      end

      return File.basename(uri).gsub(/^(.*?)\?.*$/, '\1')
    end
  end
end