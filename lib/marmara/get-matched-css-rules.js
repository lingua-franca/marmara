(function() {
    function cleanSelector(selector) {
      var elements = selector.replace(/(\s*[>+~]\s*)/g, ' $1 ').split(/\s+/);
      var newElements = [];
      for (var i = 0; i < elements.length; i++) {
        var parts = elements[i].split(/:+/);
          var element = parts[0];
        var pseudoElements = [];
        for (var j = 1; j < parts.length; j++) {
          if (parts[j].match(/^((?:first|last|nth)\-(child|of\-type)|not)/)) {
            pseudoElements.push(parts[j]);
          }
        }
        if (pseudoElements.length) {
          element += ':' + pseudoElements.join(':');
        }
        newElements.push(element);
      }
      return newElements.join(' ') || '*';
    }

    var domNodes = document.querySelectorAll('*');
    var styleSheets = document.styleSheets;
    var sheets = [];
    var rules = [];
    var sheetInfo = {};

    for (var i = 0; i < styleSheets.length; i++) {
      if (styleSheets[i] && styleSheets[i].href) {
        sheets.push(styleSheets[i].href);
        sheetInfo[styleSheets[i].href] = [];
        var sheetRules = [];
        for (var j = 0; styleSheets[i] && styleSheets[i].cssRules && j < styleSheets[i].cssRules.length; j++) {
          var rule = styleSheets[i].cssRules[j];
          // console.log(rule.selectorText);
          if (rule.selectorText) {
            // console.log('{' + rule.selectorText + '}');
            var selectors = rule.selectorText.split(/\s*,\s*/);
            var usedSelectors = [];
            for (var k = 0; k < selectors.length; k++) {
              // console.log('<' + selectors[k] + '>');
              selector = cleanSelector(selectors[k]);//.replace(/(\b):/, '$1*');
              try {
                if (document.querySelector(selector)) {
                  usedSelectors.push(selectors[k]);
                }
              } catch (e) {
                console.log('Error parsing: ' + selectors[k]);
              }
            }
            if (usedSelectors.length) {
              rules.push(rule.cssText);//{
              //   rule: rule.cssText,
              //   sheet: styleSheets[i].href,
              //   selectors: usedSelectors
              // });
            }
            sheetRules.push({
                rule: rule.cssText,
                selectors: selectors,
                usedSelectors: usedSelectors
              });
          }
        }
        sheetInfo[styleSheets[i].href] = sheetRules;
      }
    }

    // var pseudoElements = [null, 'before', 'after'];

    // for (node in domNodes) {
    //   for (var j = 0; j < pseudoElements.length; j++) {
    //     var cssRules = window.getMatchedCSSRules(domNodes[node], pseudoElements[j]);
    //     for (var i = 0; cssRules && i < cssRules.length; i++) {
    //       rule = cssRules[i];
    //       if (rule != undefined && rule.cssText != undefined) {
    //         rules.push(rule.cssText);
    //       }
    //     }
    //   }
    // }

    // return {
    //   sheets: sheets,
    //   rules: rules
    // };
    return sheetInfo;
})()
