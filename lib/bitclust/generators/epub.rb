require 'fileutils'
require 'tmpdir'
require 'erb'

require 'bitclust/subcommands/statichtml_command'

module BitClust
  module Generators
    class EPUB
      def initialize(options = {})
        @options = options.dup
        @outputdir        = options[:outputdir]
        @templatedir      = options[:templatedir]
        @catalog          = options[:catalog]
        @themedir         = options[:themedir]
        @fs_casesensitive = options[:fs_casesensitive]
        @keep             = options[:keep]
        @verbose          = options[:verbose]
      end

      CONTENTS_DIR_NAME = 'OEBPS'

      def generate
        make_epub_directory do |epub_directory|
          contents_directory = epub_directory + CONTENTS_DIR_NAME
          copy_static_files(@templatedir, epub_directory)

          html_options = @options.dup
          html_options[:outputdir] = contents_directory
          generate_xhtml_files(html_options)

          generate_contents_file(@options[:templatedir], epub_directory, @options[:fs_casesensitive])
          pack_epub(@options[:outputdir] + @options[:filename], epub_directory)
        end
      end

      def make_epub_directory
        dir = Dir.mktmpdir("epub-", @outputdir)
        yield Pathname.new(dir)
      ensure
        FileUtils.rm_r(dir, :secure => true, :verbose => @verbose) unless @keep
      end

      def copy_static_files(template_directory, epub_directory)
        FileUtils.cp(template_directory + "mimetype", epub_directory, :verbose => @verbose)
        FileUtils.cp(template_directory + "nav.xhtml", epub_directory, :verbose => @verbose)
        FileUtils.mkdir_p(epub_directory + "META-INF", :verbose => @verbose)
        FileUtils.cp(template_directory + "container.xml", epub_directory + "META-INF", :verbose => @verbose)
      end

      def generate_xhtml_files(options)
        argv = [
          "--outputdir=#{@outputdir}",
          "--templatedir=#{@templatedir}",
          "--catalog=#{@catalog}",
          "--themedir=#{@themedir}",
          "--suffix=.xhtml",
        ]
        argv << "--fs-casesensitive" if @fs_casesensitive
        argv << "--quiet" unless @verbose

        cmd = BitClust::Subcommands::StatichtmlCommand.new
        cmd.parse(argv)
        cmd.exec(argv, options)
      end

      def generate_contents_file(template_directory, epub_directory, fs_casesensitive)
        items = []
        glob_relative_path(epub_directory, "#{CONTENTS_DIR_NAME}/class/*.xhtml").each do |path|
          items << {
            :id => decodename_package(path.basename(".*").to_s, fs_casesensitive),
            :path => path
          }
        end
        items.sort_by!{|item| item[:path] }
        contents = ERB.new(File.read(template_directory + "contents"), nil, "-").result(binding)
        open(epub_directory + "contents.opf", "w") do |f|
          f.write contents
        end
      end

      def pack_epub(output_path, epub_directory)
        Dir.chdir(epub_directory.to_s) do
          system("zip -0 -X #{output_path} mimetype")
          system("zip -r #{output_path} ./* -x mimetype")
        end
      end

      def glob_relative_path(path, pattern)
        relative_paths = []
        absolute_path_to_search = Pathname.new(path).realpath
        Dir.glob(absolute_path_to_search + pattern) do |absolute_path|
          absolute_path = Pathname.new(absolute_path)
          relative_paths << absolute_path.relative_path_from(absolute_path_to_search)
        end
        relative_paths
      end

      def decodename_package(str, fs_casesensitive)
        if fs_casesensitive
          NameUtils.decodename_url(str)
        else
          NameUtils.decodename_fs(str)
        end
      end

      def last_modified
        Time.now.strftime("%Y-%m-%dT%H:%M:%SZ")
      end
    end
  end
end
