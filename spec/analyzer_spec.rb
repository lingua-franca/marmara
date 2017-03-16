require 'spec_helper'

class TestLogger
  def logs
    @logs || []
  end

  def info(str)
    @logs ||= []
    @logs << str
  end
end


describe Marmara do
  def load_test(file, variant = nil)
    visit ('file:///' + File.expand_path("spec/fixtures/pages/#{file.gsub(/\-/, '_')}/#{[file, variant].compact.join('.')}.html"))
  end

  def load_result(file, variant = nil)
    visit ('file:///' + File.expand_path("#{@output_dir}/#{[file, variant].compact.join('.')}.css.html"))
  end

  before(:all) do
    # wipe thie directory clean in case we change our tests
    FileUtils.rm_rf('spec/fixtures/results')
  end

  before do |x|
    # make the output dir different for each test
    Marmara.output_directory = @output_dir = "spec/fixtures/results/#{x.description.gsub(/\s/, '-')}"
    # use our own logger so that we can spy on the results
    Marmara.logger = @logger = TestLogger.new
  end

  describe 'Test' do
    it 'should compile a simple style sheet' do
      Marmara.start_recording
      load_test 'mass-communication'
      Marmara.record(page)
      Marmara.stop_recording

      expect(@logger.logs.count).to eq(10)
      expect(@logger.logs[0].strip).to eq('Compiling CSS coverage report...')
      expect(@logger.logs[1].strip).to eq('mass-communication.css:')
      expect(@logger.logs[2].strip).to eq('Rules: 157/157 (100.0%)')
      expect(@logger.logs[3].strip).to eq('Selectors: 161/161 (100.0%)')
      expect(@logger.logs[4].strip).to eq('Declarations: 303/303 (100.0%)')
      expect(@logger.logs[5].strip).to eq('Overall:')
      expect(@logger.logs[6].strip).to eq('Rules: 157/157 (100.0%)')
      expect(@logger.logs[7].strip).to eq('Selectors: 161/161 (100.0%)')
      expect(@logger.logs[8].strip).to eq('Declarations: 303/303 (100.0%)')
      expect(@logger.logs[9].strip).to eq('')

      load_result 'mass-communication'

      # make sure the line count is correct
      lines = page.find('#lines')
      expect(lines).to have_text '1996'
      expect(lines).not_to have_text '1997'

      expect(all('.covered').length).to be 155
      expect(all('.ignored').length).to be 155
      expect(all('.un-covered').length).to be 0
    end

    it 'should compile a minified style sheet' do
      Marmara.start_recording
      load_test 'mass-communication', :min
      Marmara.record(page)
      Marmara.stop_recording

      expect(@logger.logs.count).to eq(10)
      expect(@logger.logs[0].strip).to eq('Compiling CSS coverage report...')
      expect(@logger.logs[1].strip).to eq('mass-communication.min.css:')
      expect(@logger.logs[2].strip).to eq('Rules: 157/157 (100.0%)')
      expect(@logger.logs[3].strip).to eq('Selectors: 161/161 (100.0%)')
      expect(@logger.logs[4].strip).to eq('Declarations: 303/303 (100.0%)')
      expect(@logger.logs[5].strip).to eq('Overall:')
      expect(@logger.logs[6].strip).to eq('Rules: 157/157 (100.0%)')
      expect(@logger.logs[7].strip).to eq('Selectors: 161/161 (100.0%)')
      expect(@logger.logs[8].strip).to eq('Declarations: 303/303 (100.0%)')
      expect(@logger.logs[9].strip).to eq('')

      load_result 'mass-communication', :min

      # make sure the line count is correct
      lines = page.find('#lines')
      expect(lines).to have_text '1'
      expect(lines).not_to have_text '2'

      expect(all('.covered').length).to be 155
      expect(all('.ignored').length).to be 0
      expect(all('.un-covered').length).to be 0
    end

    it 'should ignore files' do
      Marmara.options = {
        ignore: 'http://fonts.googleapis.com/'
      }
      Marmara.start_recording
      load_test 'style-guide'
      Marmara.record(page)
      Marmara.stop_recording

      expect(@logger.logs.count).to eq(10)
      expect(@logger.logs[0].strip).to eq('Compiling CSS coverage report...')
      expect(@logger.logs[1].strip).to eq('style-guide.css:')
      expect(@logger.logs[5].strip).to eq('Overall:')
      expect(@logger.logs[9].strip).to eq('')
    end

    it 'should ignore files as an array' do
      Marmara.options = {
        ignore: ['http://fonts.googleapis.com/']
      }
      Marmara.start_recording
      load_test 'style-guide'
      Marmara.record(page)
      Marmara.stop_recording

      expect(@logger.logs.count).to eq(10)
      expect(@logger.logs[0].strip).to eq('Compiling CSS coverage report...')
      expect(@logger.logs[1].strip).to eq('style-guide.css:')
      expect(@logger.logs[5].strip).to eq('Overall:')
      expect(@logger.logs[9].strip).to eq('')
    end

    it 'should rewite file names' do
      Marmara.options = {
        ignore: [/googleapis\.com/],
        rewrite: [{
          from: /^.*\/style_guide\/(style)\-guide\.css$/,
          to: '\1'
        }]
      }
      Marmara.start_recording
      load_test 'style-guide'
      Marmara.record(page)
      Marmara.stop_recording

      expect(@logger.logs.count).to eq(10)
      expect(@logger.logs[0].strip).to eq('Compiling CSS coverage report...')
      expect(@logger.logs[1].strip).to eq('style:')
      expect(@logger.logs[5].strip).to eq('Overall:')
      expect(@logger.logs[9].strip).to eq('')

      expect(File.exist?("#{@output_dir}/style.html")).to be
    end

    it 'should create subdirectories as needed' do
      Marmara.options = {
        ignore: [/googleapis\.com/],
        rewrite: [{
          from: /^.*\/style_guide\/(style)\-guide\.css/,
          to: 'application/\1'
        }]
      }
      Marmara.start_recording
      load_test 'style-guide'
      Marmara.record(page)
      Marmara.stop_recording

      expect(@logger.logs.count).to eq(10)
      expect(@logger.logs[0].strip).to eq('Compiling CSS coverage report...')
      expect(@logger.logs[1].strip).to eq('application/style:')
      expect(@logger.logs[5].strip).to eq('Overall:')
      expect(@logger.logs[9].strip).to eq('')

      expect(File.exist?("#{@output_dir}/application/style.html")).to be
    end
  end
end
