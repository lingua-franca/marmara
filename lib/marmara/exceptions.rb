module Marmara
  class MinimumCoverageNotMetBase < Exception
    attr_reader :expected
    attr_reader :actual

    def initialize(expected, actual)
      @expected = expected
      @actual = actual
      super("Failed to meet minimum CSS #{type} coverage of #{expected}%")
    end

    def type
      raise "This exception class is abstract"
    end

    def self.assert(expected, actual)
      raise Object.const_get(self.name).new(expected, actual) if expected && expected > actual
    end
  end
  
  class MinimumRuleCoverageNotMet < MinimumCoverageNotMetBase
    def type
      'rule'
    end
  end
  
  class MinimumSelectorCoverageNotMet < MinimumCoverageNotMetBase
    def type
      'selector'
    end
  end
  
  class MinimumDeclarationCoverageNotMet < MinimumCoverageNotMetBase
    def type
      'declaration'
    end
  end
end
