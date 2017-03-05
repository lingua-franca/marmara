# Marmara
Marmara is a Ruby Gem that analyses your css during UI testing and generates a code coverage report.

![Alt text](https://i.imgur.com/sLQIJcr.png)

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

Since I also want to capture used selectors for mobile, my after step looks more like this:

```ruby
AfterStep do
  if Marmara.recording?
    Marmara.record(page)
    old_size = page.driver.browser.client.window_size
    page.driver.resize_window(600, 400)
    Marmara.record(page)
    page.driver.resize_window(*old_size)
  end
```

### 3. Stop recording and generate your output

```ruby
at_exit do
  Marmara.stop_recording if Marmara.recording?
end
```

## Development plan
This project is currently in development, please feel free to send pull requests, there's a lot more work to be done.

### TODO
1. before and after selector
1. find unused sub selectors
