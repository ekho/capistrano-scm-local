load File.expand_path('../tasks/local.rake', __FILE__)

require 'capistrano/scm'

require 'zlib'
require 'archive/tar/minitar'
include Archive::Tar
require 'tmpdir'
require 'fileutils'

class Capistrano::Local < Capistrano::SCM
  module PlainStrategy
    def check
      puts repo_url
      test! " [ -e #{repo_url} ] "
    end

    def release
      file_list = Dir.glob(File.join(repo_url, '*')).concat(Dir.glob(File.join(repo_url, '.[^.]*')))

      on release_roles :all, in: :parallel do |host|
        file_list.each { |r| upload! r, release_path, recursive: true }
      end
    end
  end

  module ArchiveStrategy
    def check
      test! " [ -e #{repo_url} ] "
    end

    def release
      archive = ''
      # preparing archive
      run_locally do
        archive = fetch(:tmp_dir, Dir::tmpdir()) + '/' + fetch(:application, 'distr') + "-#{release_timestamp}.tar.gz"
        unless File.exists?(archive)
          if File.directory?(repo_url) || !File.fnmatch('*.tar.gz', repo_url)
            Dir.chdir(repo_url) do
              Minitar.pack('.', Zlib::GzipWriter.new(File.open(archive, 'wb')))
            end
          else
            FileUtils.cp(repo_url, archive)
          end
        end
      end

      # uploading and unpacking
      on release_roles :all, in: :parallel do |host|
        upload! archive, releases_path, verbose: false
        remote_archive = File.join(releases_path, File.basename(archive))
        execute :tar, 'xzf', remote_archive, '-C', release_path
        execute :rm, '-f', remote_archive
      end

      # removing archive
      run_locally do
        execute :rm, '-f', archive
      end
    end
  end
end