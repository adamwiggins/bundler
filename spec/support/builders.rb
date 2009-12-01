module Spec
  module Builders

    def build_repo1
      build_repo gem_repo1 do
        build_gem "rake",           "0.8.7"
        build_gem "rack",           %w(0.9.1 1.0.0) do |s|
          s.executables = "rackup"
        end
        build_gem "rails",          "2.3.2" do |s|
          s.executables = "rails"
          s.add_dependency "rake"
          s.add_dependency "actionpack",     "2.3.2"
          s.add_dependency "activerecord",   "2.3.2"
          s.add_dependency "actionmailer",   "2.3.2"
          s.add_dependency "activeresource", "2.3.2"
        end
        build_gem "actionpack",     "2.3.2" do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "activerecord",   "2.3.2" do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "actionmailer",   "2.3.2" do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "activeresource", "2.3.2" do |s|
          s.add_dependency "activesupport", "2.3.2"
        end
        build_gem "activesupport",  "2.3.2"
      end
    end

    def build_repo(path)
      return if File.directory?(path)
      @_build_path = "#{path}/gems"
      yield
      @_build_path = nil
      Dir.chdir(path) { gem_command :generate_index }
    end

    def build_index(&block)
      index = Gem::SourceIndex.new
      IndexBuilder.run(index, &block) if block_given?
      index
    end

    def build_spec(name, version, &block)
      spec = Gem::Specification.new
      spec.instance_variable_set(:@name, name)
      spec.instance_variable_set(:@version, Gem::Version.new(version))
      DepBuilder.run(spec, &block) if block_given?
      spec
    end

    def build_dep(name, requirements = Gem::Requirement.default, type = :runtime)
      Gem::Dependency.new(name, requirements, type)
    end

    def build_lib(name, *args, &blk)
      build_with(LibBuilder, name, args, &blk)
    end

    def build_gem(name, *args, &blk)
      build_with(GemBuilder, name, args, &blk)
    end

  private

    def build_with(builder, name, args, &blk)
      options  = args.last.is_a?(Hash) ? args.pop : {}
      versions = args.last || "1.0"

      options[:path] ||= @_build_path

      Array(versions).each do |version|
        spec = builder.new(self, name, version)
        yield spec if block_given?
        spec._build(options)
      end
    end

    class IndexBuilder
      include Builders

      def self.run(index, &block)
        new(index).run(&block)
      end

      def initialize(index)
        @index = index
      end

      def run(&block)
        instance_eval(&block)
      end

      def add_spec(*args, &block)
        @index.add_spec(build_spec(*args, &block))
      end
    end

    class DepBuilder
      def self.run(spec, &block)
        new(spec).run(&block)
      end

      def initialize(spec)
        @spec = spec
      end

      def run(&block)
        instance_eval(&block)
      end

      def runtime(name, requirements)
        @spec.add_runtime_dependency(name, requirements)
      end
    end

    class LibBuilder
      def initialize(context, name, version)
        @context = context
        @name    = name
        @spec = Gem::Specification.new do |s|
          s.name    = name
          s.version = version
          s.summary = "This is just a fake gem for testing"
        end
        @files = { "lib/#{name}.rb" => "#{name.upcase} = '#{version}'" }
      end

      def method_missing(*args, &blk)
        @spec.send(*args, &blk)
      end

      def write(file, source)
        @files[file] = source
      end

      def executables=(val)
        Array(val).each do |file|
          write "bin/#{file}", "require '#{@name}'"
        end
        @spec.executables = Array(val)
      end

      def _build(options)
        path = options[:path] || _default_path
        @files["#{name}.gemspec"] = @spec.to_ruby if options[:gemspec]
        @files.each do |file, source|
          file = path.join(file)
          FileUtils.mkdir_p(file.dirname)
          File.open(file, 'w') { |f| f.puts source }
        end
        @spec.files = @files.keys
        path
      end

      def _default_path
        @context.tmp_path('libs', @spec.full_name)
      end
    end

    class GemBuilder < LibBuilder

      def _build(opts)
        lib_path = super(:path => @context.tmp_path(".tmp/#{@spec.full_name}"))
        Dir.chdir(lib_path) do
          destination = opts[:path] || _default_path
          FileUtils.mkdir_p(destination)
          Gem::Builder.new(@spec).build
          FileUtils.mv("#{@spec.full_name}.gem", opts[:path] || _default_path)
        end
      end

      def _default_path
        @context.gem_repo1('gems')
      end
    end
  end
end