(function() {
    var domNodes = document.querySelectorAll('*');
    var styleSheets = document.styleSheets;
    var sheets = [];

    for (var i = 0; i < styleSheets.length; i++) {
      if (styleSheets[i] && styleSheets[i].href) {
        sheets.push(styleSheets[i].href);
      }
    }

    var rules = []

    for (node in domNodes) {
      var cssRules = window.getMatchedCSSRules(domNodes[node]);
      for (var i = 0; cssRules && i < cssRules.length; i++) {
        rule = cssRules[i];
        if (rule != undefined && rule.cssText != undefined) {
          rules.push(rule.cssText);
        }
      }
    }

    return {
      sheets: sheets,
      rules: rules
    };
})()
