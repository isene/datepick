Gem::Specification.new do |s|
  s.name        = 'datepick'
  s.version     = '1.1.0'
  s.licenses    = ['Unlicense']
  s.summary     = "Datepick - Interactive Terminal Date Picker"
  s.description = "A powerful interactive terminal date picker built with rcurses. Features vim-style navigation, configurable date formats, multiple month views, and extensive keyboard shortcuts. Perfect for shell scripts and command-line workflows that need date selection. Version 1.1.0: Updated for rcurses 6.0.0 compatibility."
  s.authors     = ["Geir Isene"]
  s.email       = 'g@isene.com'
  s.files       = ["bin/datepick", "lib/datepick.rb", "README.md"]
  s.add_runtime_dependency 'rcurses', '~> 6.0'
  s.executables << 'datepick'
  s.homepage    = 'https://isene.com/'
  s.metadata    = { "source_code_uri" => "https://github.com/isene/datepick" }
end