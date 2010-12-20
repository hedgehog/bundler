require "spec_helper"

describe "bundle update" do
  describe "git sources" do
    it "floats on a branch when :branch is used" do
      build_git  "foo", "1.0"
      update_git "foo", :branch => "omg"

      install_gemfile <<-G
        git "file://#{lib_path('foo-1.0')}/.git", :branch => "omg" do
          gem 'foo'
        end
      G

      update_git "foo", :branch => "omg" do |s|
        s.write "lib/foo.rb", "FOO = '1.1'"
      end

      bundle "update"

      should_be_installed "foo 1.1"
    end

    it "updates correctly when you have like craziness" do
      build_lib "activesupport", "3.0", :path => lib_path("rails/activesupport")
      build_git "rails", "3.0", :path => "file://#{lib_path('rails')}/.git" do |s|
        s.add_dependency "activesupport", "= 3.0"
      end

      install_gemfile <<-G
        gem "rails", :git => "file://#{lib_path('rails')}/.git"
      G

      bundle "update rails"
      out.should include("Using activesupport (3.0) from file://#{lib_path('rails')}/.git (at master)")
      should_be_installed "rails 3.0", "activesupport 3.0", :gemspec_count => 2
    end

    it "floats on a branch when :branch is used and the source is specified in the update" do
      build_git  "foo", "1.0", :path => lib_path("foo")
      update_git "foo", :branch => "omg", :path => lib_path("foo")

      install_gemfile <<-G
        git "file://#{lib_path('foo')}/.git", :branch => "omg" do
          gem 'foo'
        end
      G

      update_git "foo", :branch => "omg", :path => lib_path("foo") do |s|
        s.write "lib/foo.rb", "FOO = '1.1'"
      end

      bundle "update --source foo"

      should_be_installed "foo 1.1"
    end

    it "floats on master when updating all gems that are pinned to the source even if you have child dependencies" do
      build_git "foo", :path => "file://#{lib_path('foo')}/.git"
      build_gem "bar", :to_system => true do |s|
        s.add_dependency "foo"
      end

      install_gemfile <<-G
        gem "foo", :git => "file://#{lib_path('foo')}/.git"
        gem "bar"
      G

      update_git "foo", :path => "file://#{lib_path('foo')}/.git" do |s|
        s.write "lib/foo.rb", "FOO = '1.1'"
      end

      bundle "update foo"

      should_be_installed "foo 1.1", :gemspec_count => 2
    end

    it "notices when you change the repo url in the Gemfile" do
      build_git "foo", :path => "file://#{lib_path('foo_one')}/.git"
      build_git "foo", :path => "file://#{lib_path('foo_two')}/.git"

      install_gemfile <<-G
        gem "foo", "1.0", :git => "file://#{lib_path('foo_one')}/.git"
      G

      FileUtils.rm_rf lib_path("foo_one")

      install_gemfile <<-G
        gem "foo", "1.0", :git => "file://#{lib_path('foo_two')}/.git"
      G

      err.should be_empty
      out.should include("Fetching file://#{lib_path}/foo_two/.git")
      out.should include("Your bundle is complete!")
    end


    it "fetches tags from the remote" do
      build_git "foo", :path => "file://#{lib_path('foo')}/.git"
      @remote = build_git("bar", '1.0', :path => "file://#{lib_path('bar-1.0').to_s}/.git")
      update_git "foo", :remote => "file://#{@remote.path.to_s}/.git", :path => "file://#{lib_path('foo')}/.git"
      update_git "foo", :push => "master", :path => "file://#{lib_path('foo')}/.git"

      install_gemfile <<-G
        gem 'foo', :git => "file://#{@remote.path.to_s}/.git"
      G

      # Create a new tag on the remote that needs fetching
      update_git "foo", :tag => "fubar", :path => "file://#{lib_path('foo')}/.git"
      update_git "foo", :push => "fubar", :path => "file://#{lib_path('foo')}/.git"

      gemfile <<-G
        gem 'foo', :git => "file://#{@remote.path.to_s}/.git", :tag => "fubar"
      G

      bundle "update", :exitstatus => true
      exitstatus.should == 0
    end

    describe "with submodules" do
      before :each do
        build_gem "submodule", :to_system => true do |s|
          s.write "lib/submodule.rb", "puts 'GEM'"
        end

        build_git "submodule", "1.0" do |s|
          s.write "lib/submodule.rb", "puts 'GIT'"
        end

        build_git "has_submodule", "1.0" do |s|
          s.add_dependency "submodule"
        end

        Dir.chdir(lib_path('has_submodule-1.0')) do
          `git submodule add #{lib_path('submodule-1.0')} submodule-1.0`
          `git commit -m "submodulator"`
        end
      end

      it "it unlocks the source when submodules is added to a git source" do
        install_gemfile <<-G
          git "file://#{lib_path('has_submodule-1.0')}/.git" do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        check out.should match /GEM/

        install_gemfile <<-G
          git "file://#{lib_path('has_submodule-1.0')}/.git", :submodules => true do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        out.should match /GIT/
      end

      it "it unlocks the source when submodules is removed from git source" do
        pending "This would require actually removing the submodule from the clone"
        install_gemfile <<-G
          git "file://#{lib_path('has_submodule-1.0')}/.git", :submodules => true do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        check out.should match /GIT/

        install_gemfile <<-G
          git "file://#{lib_path('has_submodule-1.0')}/.git" do
            gem "has_submodule"
          end
        G

        run "require 'submodule'"
        out.should match /GEM/
      end
    end

    it "errors with a message when the .git repo is gone" do
      build_git "foo", "1.0"

      install_gemfile <<-G
        gem "foo", :git => "file://#{lib_path('foo-1.0')}/.git"
      G

      lib_path("foo-1.0").join(".git").rmtree

      bundle :update, :expect_err => true
      out.should include(lib_path("foo-1.0").to_s)
    end

  end
end
