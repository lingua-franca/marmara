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
      old_results = File.exists?(TMP_FILE) ? JSON.parse(File.read(TMP_FILE), quirks_mode: true) : {'sheets' => [], 'rules' => []}
      old_results['sheets'] += result['sheets']
      old_results['rules'] += result['rules']
      old_results['sheets'].uniq!
      old_results['rules'].uniq!
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
      begin
        @last_driver.evaluate_script(script)
      rescue Exception => e
        puts e.to_s
        puts script
      end
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

      # parse matched rules
      rules = []
      results['rules'].each do |rule|
        parser = CssParser::Parser.new
        parser.load_string!(rule)
        parser.each_rule_set do |rule_set|
          rules << {
            set: rule_set,
            normalized: rule
          }
        end
      end

      # collect all of the rules indexes that were covered
      covered_rules = Set.new # use a set so that we get unique values
      # collect all of the sheets so that we can calculate rule coverage
      sheets = CssParser::Parser.new

      # go through all of the style sheets found
      results['sheets'].each do |uri|
        sheet_covered_rules = []
        
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
          sheets.load_uri!(uri)
          # take comments out of the equation
          sheet = original_sheet.gsub(/(\/\*.*?\*\/|@(?:charset|import)\s+.*?;)/m) { |m| ' ' * m.length }

          rules.each_with_index do |rule, index|
            rule_regex = rule[:set].selectors.collect { |sel| Regexp.escape(sel) }.join('\s*,\s*') + '\s*\{.*?\}'
            sheet.scan(Regexp.new(rule_regex, Regexp::IGNORECASE | Regexp::MULTILINE)) do |match|
              offset = Regexp.last_match.offset(0)
              sheet_rule = normalize_rule(match)
              if sheet_rule.to_s == rule[:normalized]
                sheet_covered_rules << {
                  rule: sheet_rule.to_s,
                  offset: offset,
                  state: :covered
                }
                covered_rules << index
              end
            end
          end

          original_sheet.scan(Regexp.new('\s*(?:\/\*.*?\*\/|@(?:charset|import)\s+.*?;)\s*', Regexp::MULTILINE)) do |match|
            offset = Regexp.last_match.offset(0)
            sheet_covered_rules << {
              rule: match,
              offset: offset,
              state: :ignored
            }
          end

          original_sheet.scan(Regexp.new('(@media.*?\{).*?\}\s*(\})', Regexp::IGNORECASE | Regexp::MULTILINE)) do |match|
            offset = Regexp.last_match.offset(1)
            sheet_covered_rules << {
              rule: match[1],
              offset: offset,
              state: :ignored
            }
            offset = Regexp.last_match.offset(2)
            sheet_covered_rules << {
              rule: match[2],
              offset: offset,
              state: :ignored
            }
          end

          sheet_covered_rules.sort_by! { |r| r[:offset].first }

          states = {
            covered: '<pre class="covered">',
            ignored: '<pre class="ignored">',
            not_covered: '<pre class="not-covered">'
          }
          end_covered = '</pre>'
          sheet_html = ''
          @last_index = 0
          sheet_covered_rules.each do |rule|
            uncovered_str = original_sheet[@last_index...rule[:offset][0]]
            sheet_html += states[:not_covered] + CGI.escapeHTML(uncovered_str) + end_covered if uncovered_str
            sheet_html += states[rule[:state]] + CGI.escapeHTML(original_sheet[rule[:offset][0]...rule[:offset][1]]) + end_covered
            @last_index = rule[:offset][1]
          end
          uncovered_str = original_sheet[@last_index..original_sheet.length]
          sheet_html += states[:not_covered] + uncovered_str + end_covered if uncovered_str
          sheet_html.gsub!(/\n/, '<br>')
          lines = (1..original_sheet.lines.count).to_a.join("\n")
          File.open(File.join(output_directory, File.basename(uri) + '.html'), 'wb') do |f|
            f.write(get_style_sheet_html.gsub('%{lines}', lines).gsub('%{style_sheet}', sheet_html))
          end
        end
      end

      sheet_rules = []
      sheets.each_rule_set do |rule_set|
        sheet_rules << rule_set
      end

      puts "\n    CSS Coverage: #{covered_rules.count}/#{sheet_rules.count} (#{((covered_rules.count.to_f / sheet_rules.count.to_f) * 100.0).round(2)}%)\n\n"
    end
  end
end
