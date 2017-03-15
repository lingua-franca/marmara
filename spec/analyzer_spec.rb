require 'spec_helper'

describe Marmara do
  before do |x|
    # puts " == #{x.description} == "
  end

  describe 'Test' do
    it 'should compile a simple style sheet as expected' do
      Marmara.output_directory = 'spec/fixtures/results'
      Marmara.start_recording
      visit ('file:///' + File.expand_path('spec/fixtures/pages/style_guide/style-guide.html'))
      Marmara.record(page)
      Marmara.stop_recording
    end

    it 'should compile a minified style sheet as expected' do
      Marmara.output_directory = 'spec/fixtures/results'
      Marmara.start_recording
      visit ('file:///' + File.expand_path('spec/fixtures/pages/style_guide/style-guide.min.html'))
      Marmara.record(page)
      Marmara.stop_recording
    end
  end

end
