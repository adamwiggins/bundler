require "rubygems/source_index"

module Bundler
  class VersionConflict < StandardError; end

  class Manifest
    attr_reader :filename, :sources, :dependencies, :path

    def initialize(filename, sources, dependencies, bindir, path, rubygems, system_gems)
      @filename     = filename
      @sources      = sources
      @dependencies = dependencies
      @bindir       = bindir || repository.path.join("bin")
      @path         = path
      @rubygems     = rubygems
      @system_gems  = system_gems
    end

    def install(update)
      fetch(update)
      repository.install_cached_gems(:bin_dir => @bindir)
      # Cleanup incase fetch was a no-op
      repository.cleanup(gems)
      create_environment_file(repository.path)
      Bundler.logger.info "Done."
    end

    def gems
      deps = dependencies
      deps = deps.map { |d| d.to_gem_dependency }
      Resolver.resolve(deps, repository.source_index)
    end

    def environments
      envs = dependencies.map {|dep| Array(dep.only) + Array(dep.except) }.flatten
      envs << "default"
    end

  private

    def finder
      @finder ||= Finder.new(*sources)
    end

    def repository
      @repository ||= Repository.new(@path, @bindir)
    end

    def fetch(update)
      return unless update || !all_gems_installed?

      unless bundle = Resolver.resolve(gem_dependencies, finder)
        gems = @dependencies.map {|d| "  #{d.to_s}" }.join("\n")
        raise VersionConflict, "No compatible versions could be found for:\n#{gems}"
      end

      # Cleanup here to remove any gems that could cause problem in the expansion
      # phase
      #
      # TODO: Try to avoid double cleanup
      repository.cleanup(bundle)
      bundle.download(repository)
    end

    def gem_dependencies
      @gem_dependencies ||= dependencies.map { |d| d.to_gem_dependency }
    end

    def all_gems_installed?
      downloaded_gems = {}

      Dir[repository.path.join("cache", "*.gem")].each do |file|
        file =~ /\/([^\/]+)-([\d\.]+)\.gem$/
        name, version = $1, $2
        downloaded_gems[name] = Gem::Version.new(version)
      end

      gem_dependencies.all? do |dep|
        downloaded_gems[dep.name] &&
        dep.version_requirements.satisfied_by?(downloaded_gems[dep.name])
      end
    end

    def create_environment_file(path)
      FileUtils.mkdir_p(path)

      specs      = gems
      spec_files = spec_files_for_specs(specs, path)
      load_paths = load_paths_for_specs(specs)
      bindir     = @bindir.relative_path_from(path).to_s
      filename   = @filename.relative_path_from(path).to_s

      File.open(path.join("environment.rb"), "w") do |file|
        template = File.read(File.join(File.dirname(__FILE__), "templates", "environment.erb"))
        erb = ERB.new(template, nil, '-')
        file.puts erb.result(binding)
      end
    end

    def load_paths_for_specs(specs)
      load_paths = []
      specs.each do |spec|
        gem_path = Pathname.new(spec.full_gem_path)

        if spec.bindir
          load_paths << gem_path.join(spec.bindir).relative_path_from(@path).to_s
        end
        spec.require_paths.each do |path|
          load_paths << gem_path.join(path).relative_path_from(@path).to_s
        end
      end
      load_paths
    end

    def spec_files_for_specs(specs, path)
      files = {}
      specs.each do |s|
        files[s.name] = File.join("specifications", "#{s.full_name}.gemspec")
      end
      files
    end
  end
end
