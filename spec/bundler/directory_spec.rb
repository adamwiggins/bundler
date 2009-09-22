require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe "Faking gems with directories" do

  describe "with a simple directory structure" do
    2.times do |i|
      describe "stubbing out a gem with a directory -- #{i}" do
        before(:each) do
          path = fixture_dir.join("very-simple")
          path = path.relative_path_from(bundled_app) if i == 1

          install_manifest <<-Gemfile
            clear_sources
            source "file://#{gem_repo1}"
            gem "very-simple", "1.0", :vendored_at => "#{path}"
          Gemfile
        end

        it "does not download the gem" do
          tmp_gem_path.should_not include_cached_gem("very-simple-1.0")
          tmp_gem_path.should     include_installed_gem("very-simple-1.0")
          tmp_gem_path.should_not include_vendored_dir("very-simple")
        end

        it "has very-simple in the load path" do
          out = run_in_context "require 'very-simple' ; puts VerySimpleForTests"
          out.should == "VerySimpleForTests"
        end

        it "does not remove the directory during cleanup" do
          install_manifest <<-Gemfile
            clear_sources
            source "file://#{gem_repo1}"
          Gemfile

          fixture_dir.join("very-simple").should be_directory
        end

        it "can bundle --cached" do
          %w(doc gems specifications environment.rb).each do |file|
            FileUtils.rm_rf(tmp_gem_path(file))
          end

          Dir.chdir(bundled_app) do
            out = gem_command :bundle, "--cached"
            out = run_in_context "require 'very-simple' ; puts VerySimpleForTests"
            out.should == "VerySimpleForTests"
          end
        end
      end
    end

    describe "bad directory stubbing" do
      it "raises an exception unless the version is specified" do
        lambda do
          install_manifest <<-Gemfile
            clear_sources
            gem "very-simple", :vendored_at => "#{fixture_dir.join("very-simple")}"
          Gemfile
        end.should raise_error(ArgumentError, /:at/)
      end

      it "raises an exception unless the version is an exact version" do
        lambda do
          install_manifest <<-Gemfile
            clear_sources
            gem "very-simple", ">= 0.1.0", :vendored_at => "#{fixture_dir.join("very-simple")}"
          Gemfile
        end.should raise_error(ArgumentError, /:at/)
      end
    end
  end

  it "checks the root directory for a *.gemspec file" do
    path = lib_builder("very-simple", "1.0", :path => tmp_path("very-simple")) do |s|
      s.add_dependency "rack", ">= 0.9.1"
      s.write "lib/very-simple.rb", "class VerySimpleForTests ; end"
    end

    install_manifest <<-Gemfile
      clear_sources
      source "file://#{gem_repo1}"
      gem "very-simple", "1.0", :vendored_at => "#{path}"
    Gemfile

    tmp_gem_path.should_not include_cached_gem("very-simple-1.0")
    tmp_gem_path.should include_cached_gem("rack-0.9.1")
    tmp_gem_path.should include_installed_gem("rack-0.9.1")
  end

  it "recursively finds all gemspec files in a directory" do
    lib_builder("first", "1.0")
    lib_builder("second", "1.0") do |s|
      s.add_dependency "first", ">= 0"
      s.write "lib/second.rb", "require 'first' ; SECOND = 'required'"
    end

    install_manifest <<-Gemfile
      clear_sources
      gem "second", "1.0", :vendored_at => "#{tmp_path('dirs')}"
    Gemfile

    out = run_in_context <<-RUBY
      Bundler.require_env
      puts FIRST
      puts SECOND
    RUBY

    out.should == "required\nrequired"
  end

  it "copies bin files to the bin dir" do
    path = lib_builder('very-simple', '1.0', :path => tmp_path("very-simple")) do |s|
      s.executables << 'very_simple'
      s.write "bin/very_simple", "#!#{Gem.ruby}\nputs 'OMG'"
    end

    install_manifest <<-Gemfile
      clear_sources
      gem "very-simple", :vendored_at => "#{tmp_path('very-simple')}"
    Gemfile

    tmp_bindir('very_simple').should exist
    `#{tmp_bindir('very_simple')}`.strip.should == 'OMG'
  end
end