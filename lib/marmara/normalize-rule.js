(function(rule) {
    var style = document.createElement("style");
    style.appendChild(document.createTextNode(""));
    document.head.appendChild(style);
    style.sheet.insertRule(rule, 0);
    var result = style.sheet.cssRules[0].cssText;
    document.head.removeChild(style);
    return result;
})
