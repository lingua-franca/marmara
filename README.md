# Marmara [![Build Status](https://travis-ci.org/lingua_franca/marmara.png?branch=master)](https://travis-ci.org/lingua_franca/marmara) [![Gem Version](https://badge.fury.io/rb/marmara.svg)](https://badge.fury.io/rb/marmara)
Marmara is a Ruby Gem that analyses your css during UI testing and generates a code coverage report.

![Example screenshot of Marmara output](https://i.imgur.com/N7J6wjD.png)

## Why is CSS code coverage important?
CSS code coverage is a little different than traditional code coverage.

### Discovering Unused CSS
Removing dead CSS code will decrease the number size of your CSS that gets delivered to your user and decreases the number amount of work that client will need to perform once it receives that file, both should lead to an faster website overall and may save you server costs.

While this tool will tell you which CSS rules were untouched during testing, you shouldn't always consider a deeper analysis before modifying your source. Imagine that you have a report that looks ike the following:

```diff
 /*
  * Make all links red
  */
+ a {
+     color: red;
+     opacity: 0.9;
+ }

 /*
  * We used to colour our links blue, maybe we should remove this rule...
  */
- a.my-old-style {
-     color: blue;
- }

 /*
  * Do some old IE fixing
  */
- html.ie-9 a {
-     filter: alpha(opacity=90);
- }
```

As you can see here, the first `a` rule was used, so we definitely want to keep it but there is an older rule `a.my-old-style` which can probably be safely removed. The last rule however is a fix for older browsers, so we should probably consider keeping it.

### Safer CSS Refactoring
Sometimes our CSS files become monoliths when it would be much better to split up a file into smaller modules. By running a subset of your tests, you can safely determine where files can be split.

### Discovering Untested Features
With traditional code coverage, this is the most important factor in improving your code base, with CSS testing it is still important but to a lesser degree. If you look back at the first example, the fact that these rules are not covered may mean that you are actually not testing important features. You may want to consider adding tests for IE by using a different user agent or setting the html class programmatically.

## Set up
This project has yet only been set up in a Rails Capybara/Poltergeist environment, more work may need to be done to get it woking in other environment.

It is important to run `Marmara.start_recording` before you run any tests and `Marmara.stop_recording` after testing is complete but currently the call to `Marmara.stop_recording` needs to happen before poltergeist as closed its connection with phantomjs. It would probably be best for us to spin up our own process to avoid this.

### 1. Create a Rake task

I'm using Cucumber, so I added a new rake task that looks like this:

```ruby
task "css:cover" do
  Marmara.start_recording
  Rake::Task[:cucumber].execute
end
```

### 2. Capture your output

```ruby
AfterStep do
  Marmara.record(page) if Marmara.recording?
end
```

### 3. Stop recording and generate your output

```ruby
at_exit do
  Marmara.stop_recording if Marmara.recording?
end
```

You can also integrate with your existing tests to run all of the time if you like. To do that you can simply include `Marmara.start_recording` near the top of your `env.rb` file.

## Execution

If you're using a rake task like I have described above, simply execute:

```bash
rake css:cover
```

You should see your tests exceute normally but after your tests complete you should see:

```bash
Compiling CSS coverage report...

    application.css:
              Rules: 50/100 (50.00%)
              Selectors:  75/200 (37.50%)
              Declarations:  333/500 (66.67%)

    fonts.css:
              Rules: 2/2 (100.00%)
              Selectors:  0/0 (NaN%)
              Declarations:  2/2 (100.00%)

    Overall:
              Rules: 52/102 (50.98%)
              Selectors:  75/200 (37.50%)
              Declarations:  2/2 (66.73%)
```

A **rule** is matched whenever at least one selector is covered, each **selector** within a rule is covered independently, **declarations** are each property and value pair within a rule.

You should now be able to find coverage report in your `log/css` directory. In the example above you should expect to find the files:

```PowerShell
[my_app]
  ├ [app]
  │   └ # ...
  ├ [log]
  │   ├ [css]
  │   │   ├ application.css.html
  │   │   └ fonts.css.html
  │   ├ # application.log
  │   └ # ...
  └ [spec]
      └ # ...
```

Open `application.css.html` or `fonts.css.html` in your browser to display your line coverage report.

## Configuration

### Output location
You can change the output location of your coverage reports by setting:

```Ruby
Marmara.output_directory = '../build/logs'
Marmara.start_recording
```

You can also pass the output directory as an value to the options hash:

```Ruby
Marmara.options = {
  output_directory: '../build/logs'
}
```

Set the `output_directory` before you start recording and you should find your HTML reports located in the directory you provided. *Note that this directory will removed and re-created each time the tests are run.*

### Ignoring Files
You can ignore files by passing a string, regular expression, or array or strings or regular expressions using the `:ignore` option:

```Ruby
# Ignore all files coming from http://fonts.googleapis.com/
Marmara.options = {
  ignore: 'http://fonts.googleapis.com/'
}

# Ignore all files containing 'google'
Marmara.options = {
  ignore: /google/
}

# Ignore all files containing google or adobe
Marmara.options = {
  ignore: [/google/, /adobe/]
}

# Ignore a specific file
Marmara.options = {
  ignore: /font\-awesome\.css$/
}
```

### Setting minimum coverage
By default Marmara will not cause your tests to fail even if you have 0% coverage. To enable this, set the `:minimum` option:

```Ruby
Marmara.options = {
  minimum: {
    rules: 80,
    selectors: 90,
    declarations: 90
  }
 }
```

The values represent persentages and each value is optional, if a value is not present the resepctive assertion will not be made.

If the respective overall coverage percentage doest not meet your minimum, your tests should fail and you should see a message that looks like:

```bash
Failed to meet minimum CSS rule coverage of 80%
```
