require 'open-uri'
require 'cgi'
require 'cgi'
require 'css_parser'

module Marmara

  PSEUDO_CLASSES = /^((first|last|nth|nth\-last)\-(child|of\-type)|not|empty)/

  class << self
    
    def output_directory
      @output_directory || 'log/css'
    end

    def output_directory=(dir)
      @output_directory = dir
    end

    def start_recording
      FileUtils.rm_rf(output_directory)
      ENV['_marmara_record'] = '1'
    end
    
    def stop_recording
      ENV['_marmara_record'] = nil
      log "\nCompiling CSS coverage report..."
      FileUtils.mkdir_p(output_directory)
      analyze
    end
    
    def recording?
      return ENV['_marmara_record'] == '1'
    end

    def record(driver)
      sheets = []
      @last_html ||= nil
      html = driver.html

      # don't do anything if the page hasn't changed
      return if @last_html == html

      # cache the page so we can check again next time
      @last_html = html

      # look for all the stylesheets
      driver.all('link[rel="stylesheet"]', visible: false).each do |sheet|
        sheets << sheet[:href]
      end

      @style_sheets ||= {}
      @style_sheet_rules ||= {}

      # now parse each style sheet
      sheets.each do |sheet|
        unless @style_sheets[sheet] && @style_sheet_rules[sheet]
          @style_sheet_rules[sheet] = []
          all_selectors = {}
          all_at_rules = []

          parser = nil
          begin
            parser = CssParser::Parser.new
            parser.load_uri!(sheet, capture_offsets: true)
          rescue
            log "Error reading #{sheet}"
          end

          unless parser.nil?
            # go over each rule in the sheet
            parser.each_rule_set do |rule, media_types|
              selectors = []
              rule.each_selector do |sel, dec, spec|
                if sel.length > 0
                  # we need to look for @keyframes and @font-face coverage differently
                  if sel[0] == '@'
                    rule_type = sel[1..-1]
                    at_rule = {
                        rule: rule,
                        type: :at_rule,
                        at_rule_type: rule_type
                      }
                    case rule_type
                    when 'font-face'
                      at_rule[:property] = 'font-family'
                      at_rule[:value] = rule.get_value('font-family').gsub(/^\s*"(.*?)"\s*;?\s*$/, '\1')
                    when /^(\-\w+\-)?keyframes\s+(.*?)\s*$/
                      at_rule[:property] = ["#{$1}animation-name", "#{$1}animation"]
                      at_rule[:value] = $2
                      at_rule[:valueRegex] = [/(?:^|,)\s*(?:#{Regexp.escape(at_rule[:value])})\s*(?:,|;?$)/, /(?:^|\s)(?:#{Regexp.escape(at_rule[:value])})(?:\s|;?$)/]
                    when /^(\-moz\-document|supports)/
                      # ignore these types
                      at_rule[:used] = true
                    end

                    if at_rule[:value]
                      at_rule[:valueRegex] ||= /(?:^|,)\s*(?:#{Regexp.escape(at_rule[:value])}|\"#{Regexp.escape(at_rule[:value])}\")\s*(?:,|;?$)/
                    end

                    # store all the info that we collected about the rule
                    @style_sheet_rules[sheet] << at_rule
                  else
                    # just a regular selector, collect it
                    selectors << {
                        original: sel,
                        queryable: get_safe_selector(sel)
                      }
                    all_selectors[get_safe_selector(sel)] ||= false

                    # store all the info that we collected about the rule
                    @style_sheet_rules[sheet] << {
                        rule: rule,
                        type: :rule,
                        selectors: selectors,
                        used_selectors: [false] * selectors.count
                      }
                  end
                else
                  # store all the info that we collected about the rule
                  @style_sheet_rules[sheet] << {
                      rule: rule,
                      type: :unknown
                    }
                end
              end
            end

            # store info about the stylesheet
            @style_sheets[sheet] = {
              css: download_style_sheet(sheet),
              all_selectors: all_selectors,
              all_at_rules: all_at_rules,
              included_with: Set.new
            }
          end
          @style_sheets[sheet][:included_with] += sheets
        end

        # gather together only the selectors that haven't been spotted yet
        selectors_to_find = @style_sheets[sheet][:all_selectors].select{|k,v|!v}.keys

        # don't do anything unless we have to
        if selectors_to_find.length > 0
          # and search for them in this document
          found_selectors = evaluate_script("(function(selectors) {
              var results = {};
              for (var i = 0; i < selectors.length; i++) {
                results[selectors[i]] = !!document.querySelector(selectors[i]);
              }
              return results;
            })(#{selectors_to_find.to_json})", driver)

          # now merge the results back in
          found_selectors.each { |k,v| @style_sheets[sheet][:all_selectors][k] ||= v }

          # and mark each as used if found
          @style_sheet_rules[sheet].each_with_index do |rule, rule_index|
            if rule[:type] == :rule
              rule[:selectors].each_with_index do |sel, sel_index|
                @style_sheet_rules[sheet][rule_index][:used_selectors][sel_index] ||= @style_sheets[sheet][:all_selectors][sel[:queryable]]
              end
            end
          end
        end
      end
    end

    def get_safe_selector(sel)
      sel.gsub!(/:+(.+)([^\-\w]|$)/) do |match|
        ending = Regexp.last_match[2]
        Regexp.last_match[1] =~ PSEUDO_CLASSES ? match : ending
      end
      sel.length > 0 ? sel : '*'
    end

    def get_style_sheet_html
      @style_sheet_html ||= File.read(File.join(File.dirname(__FILE__), 'marmara', 'style-sheet.html'))
    end

    def evaluate_script(script, driver = @last_driver)
      @last_driver = driver
      @last_driver.evaluate_script(script)
    end

    def analyze
      # start compiling the overall stats
      overall_stats = {
          'Rules' => { match_count: 0, total: 0 },
          'Selectors' => { match_count: 0, total: 0 },
          'Declarations' => { match_count: 0, total: 0 }
        }

      # go through all of the style sheets found
      #get_latest_results.each do |uri, rules|
      @style_sheet_rules.each do |uri, rules|
        # download the style sheet
        original_sheet = (@style_sheets[uri] || {})[:css]

        if original_sheet
          # if we can download it calculate the overage
          coverage = get_coverage(uri) #original_sheet, rules)
          # and generate the report
          html = generate_html_report(original_sheet, coverage[:covered_rules])

          # output stats for this file
          log_stats(get_report_filename(uri), {
              'Rules' => {
                match_count: coverage[:matched_rules],
                total: coverage[:total_rules]
              },
              'Selectors' => {
                match_count: coverage[:matched_selectors],
                total: coverage[:total_selectors]
              },
              'Declarations' => {
                match_count: coverage[:matched_declarations],
                total: coverage[:total_declarations]
              }
            })

          # add to the overall stats
          overall_stats['Rules'][:match_count] += coverage[:matched_rules]
          overall_stats['Rules'][:total] += coverage[:total_rules]
          overall_stats['Selectors'][:match_count] += coverage[:matched_selectors]
          overall_stats['Selectors'][:total] += coverage[:total_selectors]
          overall_stats['Declarations'][:match_count] += coverage[:matched_declarations]
          overall_stats['Declarations'][:total] += coverage[:total_declarations]

          # save the report
          save_report(uri, html)
        end
      end

      log_stats('Overall', overall_stats)
      log "\n"
    end

    def download_style_sheet(uri)
      open_attempts = 0
      begin
        open_attempts += 1
        uri = Addressable::URI.parse(uri.to_s)

        # remote file
        if uri.scheme == 'https'
          uri.port = 443 unless uri.port
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        else
          http = Net::HTTP.new(uri.host, uri.port)
        end

        res = http.get(uri.request_uri, {'Accept-Encoding' => 'gzip'})
        src = res.body.force_encoding("UTF-8")

        case res['content-encoding']
          when 'gzip'
            io = Zlib::GzipReader.new(StringIO.new(res.body))
            src = io.read
          when 'deflate'
            io = Zlib::Inflate.new
            src = io.inflate(res.body)
        end

        if String.method_defined?(:encode)
          src.encode!('UTF-8', 'utf-8')
        else
          ic = Iconv.new('UTF-8//IGNORE', 'utf-8')
          src = ic.iconv(src)
        end

        return src
      rescue Exception => e
        sleep(1)
        retry if open_attempts < 4
        log "\tFailed to open #{uri}"
        log e.to_s
      end
      return nil
    end

    def save_report(uri, html)
      File.open(get_report_path(uri), 'wb:UTF-8') { |f| f.write(html) }
    end

    def get_report_path(uri)
      File.join(output_directory, get_report_filename(uri) + '.html')
    end

    def get_report_filename(uri)
      File.basename(uri)
    end

    def is_property_covered(sheets, property, valueRegex)
      # iterate over each sheet
      sheets.each do |uri|
        # each rule in each sheet
        @style_sheet_rules[uri].each do |rule|
          # check to see if this property and value matches
          if rule[:type] == :rule
            # if at least one selector was covered we can return true now
            valueRegexs = [*valueRegex]
            [*property].each_with_index do |prop, i|
              if rule[:rule].get_value(prop) =~ valueRegexs[i] && rule[:used_selectors].reduce(&:|)
                return true
              end
            end
          end
        end
      end

      # the rule wasn't covered
      return false
    end

    def get_coverage(uri)
      total_selectors = 0
      covered_selectors = 0

      total_rules = @style_sheet_rules[uri].count
      covered_rules = 0

      total_declarations = 0
      covered_declarations = 0

      sheet_covered_rules = []
      @style_sheet_rules[uri].each do |rule|
        coverage = {
            offset: [
                rule[:rule].offset.first,
                rule[:rule].offset.last                
              ],
          }

        if rule[:type] == :at_rule
          covered = is_property_covered(@style_sheets[uri][:included_with], rule[:property], rule[:valueRegex])
          
          total_selectors += 1
          total_rules += 1
          total_declarations += 1

          if covered
            covered_selectors += 1
            covered_rules += 1
            covered_declarations += 1
            coverage[:state] = :covered
          else
            coverage[:state] = :not_covered
          end
        elsif rule[:type] == :rule
          some_covered = rule[:used_selectors].reduce(&:|)
          total_selectors += rule[:used_selectors].count

          if some_covered
            covered_rules += 1
            
            rule[:rule].each_declaration do
              total_declarations += 1
              covered_declarations += 1
            end

            coverage[:state] = :covered
            if rule[:used_selectors].reduce(&:&)
              covered_selectors += rule[:used_selectors].count
            else
              original_selectors, = @style_sheets[uri][:css].byteslice(rule[:rule].offset).split(/\s*\{/, 2)
              selector_i = 0

              original_selectors.scan(/(?<=^|,)\s*(.*?)\s*(?=,|$)/m) do |match|
                is_covered = rule[:used_selectors][selector_i] ? :covered : :not_covered
                covered_selectors += 1 if is_covered
                sheet_covered_rules << {
                  offset: [
                      coverage[:offset][0] + Regexp.last_match.offset(0).first,
                      coverage[:offset][0] + Regexp.last_match.offset(0).last
                    ],
                  state: is_covered
                }
                selector_i += 1
              end
              coverage[:offset][0] += original_selectors.length + 1
            end
          else
            rule[:rule].each_declaration do
              total_declarations += 1
            end
            
            coverage[:state] = :not_covered
          end
        end
        sheet_covered_rules << coverage
      end

      {
        covered_rules: organize_rules(sheet_covered_rules),
        total_rules: total_rules,
        matched_rules: covered_rules,
        total_selectors: total_selectors,
        matched_selectors: covered_selectors,
        total_declarations: total_declarations,
        matched_declarations: covered_declarations,
      }
    end

    def organize_rules(rules)
      # first sort the rules by the starting index
      rules.sort_by! { |r| r[:offset].first }

      # then remove unnecessary regions
      i = 0
      rules_removed = false
      while i < rules.length - 1
        # look for empty regions
        if rules[i][:offset][1] <= rules[i][:offset][0]
          # so that we don't lose our place, set the value to nil, then we'll strip the array of nils
          rules[i] = nil
          rules_removed = true
        # look for regions that should be connected
        elsif (next_rule = rules[i + 1]) && rules[i][:offset][1] == next_rule[:offset][0] && rules[i][:state] == next_rule[:state]
          # back up the next rule to start where ours does
          rules[i + 1][:offset][0] = rules[i][:offset][0]
          # and get rid of ourselves
          rules[i] = nil
          rules_removed = true
        end
        i += 1
      end

      # strip the array of nil values we may have set in the previous step
      rules.compact! if rules_removed

      # look for overlapping rules
      i = 0
      while i < rules.length
        next_rule = rules[i + 1]
        if next_rule && rules[i][:offset][1] > next_rule[:offset][0]
          # we found an overlapping rule
          # slice up this rule and add the remaining to the end of the array
          rules << {
            offset: [next_rule[:offset][1], rules[i][:offset][1]],
            state: rules[i][:state]
          }
          # and shorten the length of this rule
          rules[i][:offset][1] = next_rule[:offset][0]

          # start again
          return organize_rules(rules)
        end
        i += 1
      end
      
      # we're done!
      return rules
    end

    def generate_html_report(original_sheet, coverage)
      sheet_html = ''
      last_index = 0

      # collect the sheet html
      coverage.each do |rule|
        sheet_html += wrap_code(original_sheet.byteslice(last_index...rule[:offset][0]), :ignored)
        sheet_html += wrap_code(original_sheet.byteslice(rule[:offset][0]...rule[:offset][1]), rule[:state])
        last_index = rule[:offset][1] + 1
      end

      # finish off the rest of the file
      if last_index < original_sheet.length
        sheet_html += wrap_code(original_sheet[last_index...original_sheet.length], :ignored)
      end

      # replace line returns with HTML line breaks
      sheet_html.gsub!(/\n/, '<br>')

      # build the lines section
      lines = (1..original_sheet.lines.count).to_a.map do |line|
        "<a href=\"#L#{line}\" id=\"L#{line}\">#{line}</a>"
      end
      get_style_sheet_html.gsub('%{lines}', lines.join('')).gsub('%{style_sheet}', sheet_html)
    end

    def wrap_code(str, state)
      return '' unless str && str.length > 0

      @state_attr ||= {
        covered: 'class="covered"',
        ignored: 'class="ignored"',
        not_covered: 'class="not-covered"'
      }
      "<pre #{@state_attr[state]}><span>#{CGI.escapeHTML(str)}</span></pre>"
    end

    def rules_equal?(rule_a, rule_b)
      # sometimes the normalizer isn't very predictable, reset some equivalent rules ere
      @rule_replacements ||= {
        '(\soutline:)\s*(?:0px|0|rgb\(0,\s*0,\s*0\));' => '\1 0;'
      }
      
      # make the necessary replacements
      @rule_replacements.each do |regex, replacement|
        rule_a.gsub!(Regexp.new(regex), replacement)
        rule_b.gsub!(Regexp.new(regex), replacement)
      end

      # and test for equivalence
      return rule_a == rule_b
    end

    def log_stats(title, report)
      log "\n    #{title}:"

      report.each do |header, data|
        percent = ((data[:match_count] * 100.0) / data[:total]).round(2)
        log "          #{header}: #{data[:match_count]}/#{data[:total]} (#{percent}%)"
      end
    end

    def log(str)
      puts str
    end
  end
end
