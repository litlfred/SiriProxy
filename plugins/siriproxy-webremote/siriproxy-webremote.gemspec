# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "webRemote"
  s.version     = "0.0.1" 
  s.authors     = ["litlfred"]
  s.email       = [""]
  s.homepage    = ""
  s.summary     = %q{Forwards simple GET requests to a web server}
  s.description = %q{Saying "honey XXX YYY ZZZ" will generate the GET request http://honey/webRemote?remote=XXXX&code[0]=YYY&code[1]=ZZZZ.}

  s.rubyforge_project = "webRemote"

  s.files         = `git ls-files 2> /dev/null`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/* 2> /dev/null`.split("\n")
  s.executables   = `git ls-files -- bin/* 2> /dev/null`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
