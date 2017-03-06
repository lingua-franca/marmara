require 'open-uri'
require 'cgi'

module Marmara
  TMP_FILE = File.join(Dir.tmpdir, 'marmara.json')

  class << self
    def output_directory
      @output_directory || 'log/css'
    end

    def output_directory=(dir)
      @output_directory = dir
    end

    def start_recording
      FileUtils.rm_rf(output_directory)
      FileUtils.mkdir_p(output_directory)
      FileUtils.rm(TMP_FILE) if File.exists?(TMP_FILE)
      ENV['_marmara_record'] = '1'
    end
    
    def stop_recording
      ENV['_marmara_record'] = nil
      puts "\nCompiling CSS coverage report..."
      analyze
    end
    
    def recording?
      return ENV['_marmara_record'] == '1'
    end

    def record(driver)
      @last_driver = driver
      result = driver.evaluate_script(get_mached_css_rules)
      old_results = File.exists?(TMP_FILE) ? JSON.parse(File.read(TMP_FILE), quirks_mode: true) : {}
      result.each do |sheet, info|
        if old_results[sheet]
          info.each_with_index do |rule, i|
            old_results[sheet][i]['usedSelectors'] |= rule['usedSelectors']
          end
        else
          old_results[sheet] = info
        end
      end
      File.open(TMP_FILE, 'wb') { |f| f.write(old_results.to_json) }
    end

  private

    def get_style_sheet_html
      @style_sheet_html ||= File.read(File.join(File.dirname(__FILE__), 'marmara', 'style-sheet.html'))
    end

    def get_mached_css_rules
      @get_mached_css_rules_js ||= File.read(File.join(File.dirname(__FILE__), 'marmara', 'get-matched-css-rules.js'))
    end

    def normalize_rule_js
      @normalize_rule_js ||= File.read(File.join(File.dirname(__FILE__), 'marmara', 'normalize-rule.js'))
    end

    def normalize_rule(rule)
      script = "#{normalize_rule_js}('#{rule.gsub(/\n/, ' ').gsub(/\'/, "\\\\\'").force_encoding('UTF-8')}')"
      @last_driver.evaluate_script(script)
    end

    def get_rule(str)
      parser = CssParser::Parser.new
      parser.load_string!(str)
      parser.each_rule_set do |rule_set|
        return rule_set
      end
      return nil
    end

    def analyze
      # load the cached results
      results = File.exists?(TMP_FILE) ? JSON.parse(File.read(TMP_FILE), quirks_mode: true) : {'sheets' => [], 'rules' => []}

      overall_report = { 'Rules' => { match_count: 0, total: 0 }, 'Bytes' => { match_count: 0, total: 0 } }

      # go through all of the style sheets found
      results.each do |uri, rules|
        # download the style sheet
        original_sheet = nil
        open_attempts = 0
        begin
          open_attempts += 1
          original_sheet = open(uri).read
        rescue
          sleep(1)
          retry if open_attempts < 4
          puts "\tFailed to open #{uri}"
        end

        if original_sheet
          coverage = get_coverage(original_sheet, rules)
          html = generate_html_report(original_sheet, coverage[:covered_rules])

          filename = File.basename(uri)
          log_report(filename, {
              'Rules' => {
                match_count: coverage[:matched_rules],
                total: coverage[:total_rules],
                percent: coverage[:rule_coverage]
              },
              'Bytes' => {
                match_count: coverage[:matched_bytes],
                total: coverage[:total_bytes],
                percent: coverage[:byte_coverage]
              }
            })

          overall_report['Rules'][:match_count] += coverage[:matched_rules]
          overall_report['Rules'][:total] += coverage[:total_rules]
          overall_report['Bytes'][:match_count] += coverage[:matched_bytes]
          overall_report['Bytes'][:total] += coverage[:total_bytes]
          
          File.open(File.join(output_directory, filename + '.html'), 'wb') do |f|
            f.write(html)
          end
        end
      end

      log_report('Overall', overall_report)
      puts "\n"
    end

    def get_coverage(original_sheet, rules)
      sheet_covered_rules = []

      # take comments out of the equation
      sheet = original_sheet.gsub(/(\/\*.*?\*\/|@(?:charset|import)\s+.*?;)/m) { |m| ' ' * m.length }

      ignored_characters = 0
      matched_characters = 0
      matched_rules = Set.new # use a set because we don't duplicates

      # look for each rule in the CSS
      rules.each_with_index do |rule, index|
        selector_regexes = {}
        rule['selectors'].each do |sel|
          selector_regexes[sel] = Regexp.escape(sel).gsub(/(^| ):/, '\1\\*?:').gsub(/:+(before|after)/, ':+\1')
        end

        selector_regex = selector_regexes.values.join('\s*,\s*')
        rule_regex = selector_regex + '\s*\{.*?\}'
        sheet.scan(Regexp.new(rule_regex, Regexp::IGNORECASE | Regexp::MULTILINE)) do |match|
          offset = Regexp.last_match.offset(0)
          sheet_rule = normalize_rule(match)
          if rules_equal?(sheet_rule, rule['rule'])
            if rule['usedSelectors'].length > 0
              unless rule['usedSelectors'].length == rule['selectors'].length
                selector = match.match(Regexp.new(selector_regex, Regexp::IGNORECASE | Regexp::MULTILINE))[0]
                rule['usedSelectors'].each do |sel|
                  regex = selector_regexes[sel]
                  if selector =~ Regexp.new('(?:^|,\s*)(' + regex + '\s*,?\s*)', Regexp::IGNORECASE | Regexp::MULTILINE)
                    sheet_covered_rules << {
                      offset: [
                          Regexp.last_match.offset(1)[0] + offset[0],
                          Regexp.last_match.offset(1)[1] + offset[0]
                        ],
                      state: :covered
                    }
                  end
                end
                offset[0] += selector.length
              end
              sheet_covered_rules << {
                offset: offset,
                state: :covered
              }
              matched_characters += (offset[1] - offset[0])
              matched_rules << index
            end
          end
        end
      end

      # ignore one line @ directives
      original_sheet.scan(Regexp.new('\s*(?:\/\*.*?\*\/|@(?:charset|import)\s+.*?;)\s*', Regexp::MULTILINE)) do |match|
        offset = Regexp.last_match.offset(0)
        sheet_covered_rules << {
          offset: offset,
          state: :ignored
        }
        ignored_characters += (offset[1] - offset[0])
      end

      # ignore multiline @ directives 
      original_sheet.scan(Regexp.new('(@(?:media|font\-face).*?\{).*?\}\s*(\})', Regexp::IGNORECASE | Regexp::MULTILINE)) do |match|
        offset = Regexp.last_match.offset(1)
        sheet_covered_rules << {
          offset: offset,
          state: :ignored
        }
        ignored_characters += (offset[1] - offset[0])

        offset = Regexp.last_match.offset(2)
        sheet_covered_rules << {
          offset: offset,
          state: :ignored
        }
        ignored_characters += (offset[1] - offset[0])
      end

      # compile the result
      total_characters = original_sheet.length - ignored_characters
      {
        covered_rules: organize_rules(sheet_covered_rules),
        total_rules: rules.count,
        matched_rules: matched_rules.count,
        total_bytes: total_characters,
        matched_bytes: matched_characters,
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
      states = {
        covered: '<pre class="covered">',
        ignored: '<pre class="ignored">',
        not_covered: '<pre class="not-covered">'
      }
      end_covered = '</pre>'
      sheet_html = ''
      last_index = 0
      coverage.each do |rule|
        uncovered_str = original_sheet[last_index...rule[:offset][0]]
        sheet_html += states[:not_covered] + CGI.escapeHTML(uncovered_str) + end_covered if uncovered_str
        sheet_html += states[rule[:state]] + CGI.escapeHTML(original_sheet[rule[:offset][0]...rule[:offset][1]]) + end_covered
        last_index = rule[:offset][1]
      end
      uncovered_str = original_sheet[last_index..original_sheet.length]
      sheet_html += states[:not_covered] + uncovered_str + end_covered if uncovered_str
      sheet_html.gsub!(/\n/, '<br>')
      lines = (1..original_sheet.lines.count).to_a.join("\n")
      get_style_sheet_html.gsub('%{lines}', lines).gsub('%{style_sheet}', sheet_html)
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

    def log_report(title, report)
      puts "\n    #{title}:"

      report.each do |header, data|
        percent = ((data[:match_count] * 100.0) / data[:total]).round(2)
        puts "          #{header}: #{data[:match_count]}/#{data[:total]} (#{percent}%)"
      end
    end
  end
end
