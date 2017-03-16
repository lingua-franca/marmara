require 'css_parser'

module CssParser
  class MarmaraParser < Parser
    attr_reader :last_file_contents

    def read_remote_file(uri)
      if Gem.win_platform? && uri.scheme == 'file' && uri.path =~ /^\/[a-zA-Z]:\/[a-zA-Z]:\//
        # file scheme seems to be broken for windows, do some fixing
        uri.path = uri.path.gsub(/^\/[a-zA-Z]:\/([a-zA-Z]:\/.*)$/, '\1')
      end

      # save the output
      result = super(uri)
      @last_file_contents = result.first
      return result
    end
  end
end
