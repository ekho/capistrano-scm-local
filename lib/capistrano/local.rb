load File.expand_path('../tasks/local.rake', __FILE__)

require 'capistrano/scm'

require 'zlib'
require 'archive/tar/minitar'
include Archive::Tar
require 'tmpdir'
require 'fileutils'
require 'securerandom'
require 'rake/packagetask'
require 'pathname'

class Capistrano::Local < Capistrano::SCM
  module SCMStrategy
    def uploader
      @uploader ||= proc {
        case fetch(:scm_local_uploader, :scp)
          when :scp
            Capistrano::Local::ScpUploader.new(context)
          when :torrent
            Capistrano::Local::TorrentUploader.new(context)
          # when :rsync
          #   Capistrano::Local::RsyncUploader.new(context)
          else
            raise "Unknown scm_local_upload_strategy #{fetch(:scm_local_uploader).inspect}"
        end
      }.call
    end

    def check
      unless test! " [ -e #{repo_url} ] "
        run_locally do error "#{repo_url.inspect} does not valid path" end
        return false
      end

      begin
        return false unless uploader.check
      rescue Exception => e
        run_locally do error e end
      end
    end

    def release
      uploader.upload(repo_url, release_path)
    end
  end

  class UploaderBase
    attr_reader :context
    attr_reader :roles_filter

    def initialize(context)
      @context = context
      @roles_filter = fetch :scm_local_roles_filter, :all
    end
  end

  class ScpUploader < UploaderBase
    attr_reader :packer

    def initialize(context)
      super(context)

      @packer = TarPacker.new
    end

    def check
      true
    end

    def upload(local_path, remote_path)
      archive = nil
      packer = @packer

      run_locally do
        archive = packer.pack(local_path, fetch(:application, 'distr'))
      end

      hosts = release_roles(@roles_filter)
      remote_archive = File.join(remote_path.to_s, File.basename(archive))

      on hosts do |host|
        debug "Uploading #{local_path} to #{host}:#{remote_path} with scp"
        upload! archive, remote_path, :verbose => false
      end

      packer.unpack(hosts, remote_archive, remote_path)
    end
  end

  class TorrentUploader < UploaderBase
    def initialize(context)
      super(context)
    end

    def check
      unless test!(:which, 'horde')
        run_locally do
          error 'Selected torrent transport but Horde was not found. Please install Horde (https://github.com/naterh/Horde)'
        end
        return false
      end

      true
    end

    def upload(local_path, remote_path)
      hosts = release_roles(@roles_filter)
      hostlist = hosts.
          sort { |h1,h2| (h1.properties.fetch(:primary, false) == h2.properties.fetch(:primary, false)) ? h1.hostname <=> h2.hostname : h1.properties.fetch(:primary, false) ? -1 : 1 }.
          map{|host| puts "#{host.inspect}"; "#{host.user}@#{host.hostname}" }.
          join(',')
      log_dir = fetch(:tmp_dir, Dir::tmpdir()) + '/capistrano/horde'
      remote_auxiliary_path = nil

      on primary(@roles_filter) do
        tmp_dir = Pathname.new(capture :dirname, '$(mktemp -u)')
        remote_auxiliary_path = tmp_dir.join('capistrano').join(fetch(:application) + '-auxiliary')
      end

      run_locally do
        debug "Uploading #{local_path} to #{hostlist}:#{remote_path} with torrent using auxiliary path #{remote_auxiliary_path}"
      end

      on hosts do
        execute :mkdir, '-p', remote_auxiliary_path
      end

      run_locally do
        execute :mkdir, '-p', log_dir
        log = capture :horde, local_path, remote_auxiliary_path, '--hostlist', hostlist, '--log-dir', log_dir, '2>&1'
        halt "Upload failed! See logs in #{log_dir} or stdout:\n" + log if log.include?('FAILED with code')
      end

      on hosts do
        execute :cp, '-r', File.join(remote_auxiliary_path, '*'), remote_path
      end
    end
  end

  # class RsyncUploader < UploaderBase
  #   def initialize(context)
  #     super(context)
  #   end
  #
  #   def check
  #     unless test!(:which, 'rsync')
  #       run_locally do
  #         error 'Selected rsync transport but rsync binary was not found.'
  #       end
  #       return false
  #     end
  #
  #     true
  #   end
  #
  #   def upload(local_path, remote_path)
  #     hosts = release_roles(@roles_filter)
  #     hostlist = hosts.
  #         sort { |h1,h2| (h1.properties.fetch(:primary, false) == h2.properties.fetch(:primary, false)) ? h1.hostname <=> h2.hostname : h1.properties.fetch(:primary, false) ? -1 : 1 }.
  #         map{|host| puts "#{host.inspect}"; "#{host.user}@#{host.hostname}" }.
  #         join(',')
  #     log_dir = fetch(:tmp_dir, Dir::tmpdir()) + '/capistrano/horde'
  #     remote_auxiliary_path = nil
  #
  #     on primary(@roles_filter) do
  #       tmp_dir = Pathname.new(capture :dirname, '$(mktemp -u)')
  #       remote_auxiliary_path = tmp_dir.join('capistrano').join(fetch(:application) + '-auxiliary')
  #     end
  #
  #     run_locally do
  #       debug "Uploading #{local_path} to #{hostlist}:#{remote_path} with torrent using auxiliary path #{remote_auxiliary_path}"
  #     end
  #
  #     on hosts do
  #       execute :mkdir, '-p', remote_auxiliary_path
  #     end
  #
  #     run_locally do
  #       execute :mkdir, '-p', log_dir
  #       log = capture :horde, local_path, remote_auxiliary_path, '--hostlist', hostlist, '--log-dir', log_dir, '2>&1'
  #       halt "Upload failed! See logs in #{log_dir} or stdout:\n" + log if log.include?('FAILED with code')
  #     end
  #
  #     on hosts do
  #       execute :cp, '-r', File.join(remote_auxiliary_path, '*'), remote_path
  #     end
  #   end
  # end

  class TarPacker
    def initialize
      @compression_flag = fetch(:scm_local_tar_compression_flag, 'z')
      @file_ext = case @compression_flag
                    when 'z'
                      '.tar.gz'
                    when 'j'
                      '.tar.bz'
                    else
                      '.tar'
                  end
    end

    def check
      unless ['z', 'j', ''].include?(@compression_flag)
        run_locally do error "Unsupported compression flag #{@compression_flag.inspect}" end
        return false
      end

      true
    end

    def pack(source_path, arch_base_name)
      archive = fetch(:tmp_dir, Dir::tmpdir()) + '/capistrano/' + arch_base_name + '-' + SecureRandom.hex(6) + @file_ext

      run_locally do
        debug "Packing #{source_path} to #{archive}"

        execute :mkdir, '-p', File.dirname(archive)
        execute :rm, '-f', archive if test(:test, '-f', archive)

        if test :test, '-d', source_path || !File.fnmatch("*#{@file_ext}", source_path)
          within source_path do
            execute :tar, "#{@compression_flag}cf", archive, '.'
          end
        elsif test(:test, '-f', source_path) && File.fnmatch("*#{@file_ext}", source_path)
          execute :cp, source_path, archive
        else
          halt "Do not know how to publish #{source_path}"
        end
      end

      archive
    end

    def unpack(hosts, archive, dest_path, keep_archive = false)
      compression_flag = @compression_flag
      on hosts do |host|
        debug "Unpacking #{archive} to #{dest_path} on #{host}"
        execute :tar, "#{compression_flag}xf", archive, '-C', dest_path
        execute :rm, '-f', archive unless keep_archive
      end
    end
  end
end
