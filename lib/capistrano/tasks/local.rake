namespace :local do

  def local_strategy
    strategies = {:plain=>Capistrano::Local::PlainStrategy, :archive=>Capistrano::Local::ArchiveStrategy}

    m = fetch(:local_strategy ? :local_strategy : :archive)
    unless m.is_a?(Module)
      abort "Invalid local_strategy: " + m.to_s unless strategies.include?(m)
      m = strategies[m]
    end

    @local_strategy ||= Capistrano::Local.new(self, m)
  end

  desc 'Check that the source is reachable'
  task :check do
    run_locally do
        exit 1 unless local_strategy.check
    end
  end

  desc 'Copy repo to releases'
  task :create_release do
    on release_roles :all do
      within releases_path do
        execute :mkdir, '-p', release_path
      end
    end
    local_strategy.release
  end

  desc 'Read revision from REVISION file if exists'
  task :set_current_revision do
    unless fetch(:current_revision, false)
      revision_file = File.join(repo_url, 'REVISION')
      set :current_revision, File.exist?(revision_file) ? File.read(revision_file).strip : 'UNKNOWN'
    end
  end
end
