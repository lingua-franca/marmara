require 'open-uri'
require 'cgi'
require 'marmara/parser'
require 'marmara/config'
require 'marmara/exceptions'

module Marmara

  PSEUDO_CLASSES = /^((first|last|nth|nth\-last)\-(child|of\-type)|not|empty)/

  class << self
    include Config    

    def start_recording
      FileUtils.rm_rf(output_directory)
      ENV['_marmara_record'] = '1'

      @last_html = nil
      @style_sheets = {}
      @style_sheet_rules = {}
      @last_driver = nil
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
        unless ignore?(sheet)
          unless @style_sheets[sheet] && @style_sheet_rules[sheet]
            @style_sheet_rules[sheet] = []
            all_selectors = {}
            all_at_rules = []

            parser = nil
            begin
              parser = CssParser::MarmaraParser.new
              parser.load_uri!(sheet, capture_offsets: true)
            rescue Exception => e
              puts e.to_s
              puts "\t" + e.backtrace.join("\n\t")
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

                        # store all the info that we collected about the rule
                        @style_sheet_rules[sheet] << at_rule
                      end
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
                css: parser.last_file_contents,
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
    end

    def get_safe_selector(sel)
      sel.gsub!(/:+(.+)([^\-\w]|$)/) do |match|
        ending = Regexp.last_match[2]
        Regexp.last_match[1] =~ PSEUDO_CLASSES ? match : ending
      end
      sel.length > 0 ? sel : '*'
    end

    def get_style_sheet_html
      @style_sheet_html ||= File.read((options || {})[:html_file] || File.join(File.dirname(__FILE__), 'marmara', 'style-sheet.html'))
    end

    def get_style_sheet_css
      @style_sheet_css ||= File.read((options || {})[:css_file] || File.join(File.dirname(__FILE__), 'marmara', 'style-sheet.css'))
    end

    def evaluate_script(script, driver = @last_driver)
      @last_driver = driver
      @last_driver.evaluate_script(script)
    end

    def stat_types
      @stat_types ||= ['Rule', 'Selector', 'Declaration']
    end

    def analyze
      # start compiling the overall stats
      overall_stats = {}

      stat_types.each do |type|
        overall_stats["#{type}s"] = { match_count: 0, total: 0 }
      end

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

          stats_to_log = {}
          stat_types.each do |type|
            stats_to_log["#{type}s"] = {
                match_count: coverage["matched_#{type.downcase}s".to_sym],
                total: coverage["total_#{type.downcase}s".to_sym]
              }

            # add to the overall stats
            overall_stats["#{type}s"][:match_count] += coverage["matched_#{type.downcase}s".to_sym]
            overall_stats["#{type}s"][:total] += coverage["total_#{type.downcase}s".to_sym]
          end

          # output stats for this file
          log_stats(get_report_filename(uri), stats_to_log)

          # save the report
          save_report(uri, html)
        end
      end

      log_stats('Overall', overall_stats)
      log "\n"

      # check for minimum coverage
      if options && options[:minimum]
        stat_types.each do |type|
          Marmara.const_get("Minimum#{type}CoverageNotMet").assert(
              options[:minimum]["#{type.downcase}s".to_sym],
              ((overall_stats["#{type}s"][:match_count] * 100.0) / overall_stats["#{type}s"][:total]).round(2)
            )
        end
      end
    end

    def save_report(uri, html)
      path = get_report_path(uri)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, 'wb:UTF-8') { |f| f.write(html) }
    end

    def get_report_path(uri)
      File.join(output_directory, get_report_filename(uri) + '.html')
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

      total_rules = 0
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
          total_rules += 1
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

              selectors_length = 0
              original_selectors.split(/,/m).each_with_index do |sel, selector_i|
                sel_length = sel.length
                sel_length += 1 unless selector_i == (rule[:used_selectors].length - 1)

                is_covered = rule[:used_selectors][selector_i] ? :covered : :not_covered
                covered_selectors += 1 if is_covered
                sheet_covered_rules << {
                  offset: [
                      coverage[:offset][0] + selectors_length,
                      coverage[:offset][0] + selectors_length + sel_length
                    ],
                  state: is_covered
                }
                selectors_length += sel_length
              end

              coverage[:offset][0] += original_selectors.length
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

    def generate_html_report(original_sheet, coverage)
      sheet_html = ''
      last_index = 0

      # collect the sheet html
      coverage.each do |rule|
        sheet_html += wrap_code(original_sheet.byteslice(last_index...rule[:offset][0]), :ignored)
        sheet_html += wrap_code(original_sheet.byteslice(rule[:offset][0]...rule[:offset][1]), rule[:state])
        last_index = rule[:offset][1]
      end

      # finish off the rest of the file
      if last_index < original_sheet.length
        sheet_html += wrap_code(original_sheet[last_index...original_sheet.length], :ignored)
      end

      # build the lines section
      lines = (0..original_sheet.count("\n")).to_a.map do |_line|
        line = _line + 1
        "<a href=\"#L#{line}\" id=\"L#{line}\">#{line}</a>"
      end

      get_style_sheet_html.gsub('%{style}', get_style_sheet_css)
                          .gsub('%{lines}', lines.join(''))
                          .gsub('%{style_sheet}', sheet_html)
    end

    def wrap_code(str, state)
      return '' unless str && str.length > 0

      @state_attr ||= {
        covered: 'class="covered"',
        ignored: 'class="ignored"',
        not_covered: 'class="not-covered"'
      }
      str = CGI.escapeHTML(str).gsub(/\r?\n/, '<br>')
      "<pre #{@state_attr[state]}><span>#{str}</span></pre>"
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
  end
end
