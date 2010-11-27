module Spec
  module Matchers
    RSpec::Matchers.define :have_dep do |*args|
      dep = Bundler::Dependency.new(*args)

      match do |actual|
        actual.length == 1 && actual.all? { |d| d == dep }
      end
    end

    RSpec::Matchers.define :have_gem do |*args|
      match do |actual|
        actual.length == args.length && actual.all? { |a| args.include?(a.full_name) }
      end
    end

    RSpec::Matchers.define :have_rubyopts do |*args|
      args = args.flatten
      args = args.first.split(/\s+/) if args.size == 1

      #failure_message_for_should "Expected RUBYOPT to have options #{args.join(" ")}. It was #{ENV["RUBYOPT"]}"

      match do |actual|
        actual = actual.split(/\s+/) if actual.is_a?(String)
        args.all? {|arg| actual.include?(arg) } && actual.uniq.size == actual.size
      end
    end

    def should_be_installed(*names)
      opts = names.last.is_a?(Hash) ? names.pop : {}
      groups = Array(opts[:groups])
      groups << opts
      names.each do |name|
        name, version, platform = name.split(/\s+/)
        version_const = name == 'bundler' ? 'Bundler::VERSION' : Spec::Builders.constantize(name)
        run "require '#{name}.rb'; puts #{version_const}", *groups
        actual_version, actual_platform = out.split(/\s+/)
        check Gem::Version.new(actual_version).should == Gem::Version.new(version)
        actual_platform.should == platform
      end
    end

    alias should_be_available should_be_installed

    def should_not_be_installed(*names)
      opts = names.last.is_a?(Hash) ? names.pop : {}
      groups = Array(opts[:groups]) || []
      names.each do |name|
        name, version = name.split(/\s+/)
        run <<-R, *(groups + [opts])
          begin
            require '#{name}'
            puts #{Spec::Builders.constantize(name)}
          rescue LoadError, NameError
            puts "WIN"
          end
        R
        if version.nil? || out match /WIN/
          out.should match /WIN/
        else
          Gem::Version.new(out).should_not == Gem::Version.new(version)
        end
      end
    end

    def should_be_locked
      bundled_app("Gemfile.lock").should exist
    end

    RSpec::Matchers.define :be_with_diff do |expected|
      spaces = expected[/\A\s+/, 0] || ""
      expected.gsub!(/^#{spaces}/, '')

      failure_message_for_should do |actual|
        "The lockfile did not match.\n=== Expected:\n" <<
          expected << "\n=== Got:\n" << actual << "\n===========\n"
      end

      match do |actual|
        expected == actual
      end
    end

    def lockfile_should_be(expected)
      lock = File.read(bundled_app("Gemfile.lock"))
      lock.should be_with_diff(expected)
    end
  end
end
