load File.expand_path('../tasks/local.rake', __FILE__)

require 'capistrano/scm'

require 'zlib'
require 'archive/tar/minitar'
include Archive::Tar
require 'tmpdir'
require 'fileutils'

require 'rake/packagetask'

class Capistrano::Local < Capistrano::SCM
  module PlainStrategy
    def check
      test! " [ -e #{repo_url} ] "
    end

    def release
      file_list = Dir.glob(File.join(repo_url, '*')).concat(Dir.glob(File.join(repo_url, '.[^.]*')))

      on release_roles :all do |host|
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

      compression_flag = fetch(:scm_local_archive_compression_flag, 'z');
      case compression_flag
        when 'z'
          archive_extension = '.tar.gz'
        when 'j'
          archive_extension = '.tar.bz'
        else
          archive_extension = '.tar'
          compression_flag = ''
      end

      # preparing archive
      run_locally do
        archive = fetch(:tmp_dir, Dir::tmpdir()) + '/capistrano/' + fetch(:application, 'distr') + "-#{fetch(:current_revision, 'UNKNOWN').strip}#{archive_extension}"
        archive_sha1 = "#{archive}.sha1"
        debug "Archiving #{repo_url} to #{archive}"
        execute :mkdir, '-p', File.dirname(archive)

        if File.exists?(archive) && (!File.exists?(archive_sha1) || !test(:shasum, '-s', '-c', archive_sha1))
          execute :rm, '-f', archive
        end

        unless File.exists?(archive)
          if File.directory?(repo_url) || !File.fnmatch("*#{archive_extension}", repo_url)
            within repo_url do
              execute :tar, "c#{compression_flag}f", archive, '-C', repo_url, '.'
            end
            execute :tar, "t#{compression_flag}f", archive unless fetch(:scm_local_skip_tar_check, false)
            execute :shasum, archive, '>', archive_sha1
          else
            execute :cp, repo_url, archive
          end
        end
      end

      # uploading and unpacking
      on release_roles :all do |host|
        debug "Uploading #{archive} to #{host}:#{release_path}"
        upload! archive, releases_path, verbose: false
        remote_archive = File.join(releases_path, File.basename(archive))
        execute :tar, "x#{compression_flag}f", remote_archive, '-C', release_path
        execute :rm, '-f', remote_archive
      end

      # removing archive
      run_locally do
        execute :rm, '-f', archive
      end
    end
  end
end