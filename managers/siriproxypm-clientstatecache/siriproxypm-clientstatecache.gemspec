# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "siriproxypm-clientstatecache"
  s.version     = "0.0.3" 
  s.authors     = ["litlfred"]
  s.email       = [""]
  s.homepage    = ""
  s.summary     = %q{A Client Caching  Plugin Manager}
  s.description = %q{Plugin manager which keeps state information across multiple connections on a single client }

  s.rubyforge_project = "siriproxypm-clientstatecache"

  s.files         = `git ls-files 2> /dev/null`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/* 2> /dev/null`.split("\n")
  s.executables   = `git ls-files -- bin/* 2> /dev/null`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
end
