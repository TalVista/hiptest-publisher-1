require 'pathname'

require 'hiptest-publisher/utils'

module Hiptest
  class CliOptionError < StandardError
  end

  class CliOptionsChecker
    attr_reader :reporter, :cli_options
    def initialize(cli_options, reporter)
      @cli_options = cli_options
      @reporter = reporter
    end

    def check!
      check_config_file

      if cli_options.only == 'list'
        return
      end

      check_secret_token

      if push?(cli_options)
        check_push_file
      else
        check_output_directory
        check_actionwords_signature_file
        check_xml_file
        check_test_run_id
        check_language_and_only
      end
    end

    def check_config_file
      begin
        ParseConfig.new(cli_options.config) if present?(cli_options.config)
      rescue Errno::EACCES => err
        raise CliOptionError, "Error with --config: the file \"#{cli_options.config}\" does not exist or is not readable"
      end
    end

    def check_secret_token
      if absent?(cli_options.xml_file)
        if absent?(cli_options.token)
          raise CliOptionError, [
            "Missing argument --token: you must specify project secret token with --token=<project-token>",
            "",
            "The project secret token can be found on Hiptest in the settings section, under",
            "'Publication settings'. It is a sequence of numbers uniquely identifying your",
            "project.",
            "",
            "Note that settings section is available only to administrators of the project.",
          ].join("\n")
        end

        unless numeric?(cli_options.token)
          raise CliOptionError, "Invalid format --token=\"#{@cli_options.token}\": the project secret token must be numeric"
        end
      end
    end

    def check_push_file
      if cli_options.push
        agnostic_path = clean_path(cli_options.push)
        globbed_files = Dir.glob(agnostic_path)

        if globbed_files.length == 0
          raise CliOptionError, "Error with --push: the file \"#{cli_options.push}\" does not exist or is not readable"
        elsif globbed_files.length == 1 && globbed_files == [cli_options.push]
          if !File.readable?(agnostic_path)
            raise CliOptionError, "Error with --push: the file \"#{cli_options.push}\" does not exist or is not readable"
          elsif !File.file?(agnostic_path)
            raise CliOptionError, "Error with --push: the file \"#{cli_options.push}\" is not a regular file"
          end
        end
      end
    end

    def check_output_directory
      output_directory = clean_path(cli_options.output_directory)

      parent = first_existing_parent(output_directory)
      if !parent.writable?
        if parent.realpath === Pathname.new(cli_options.output_directory).cleanpath
          raise CliOptionError, "Error with --output-directory: the directory \"#{@cli_options.output_directory}\" is not writable"
        else
          raise CliOptionError, "Error with --output-directory: the directory \"#{@cli_options.output_directory}\" can not be created because \"#{parent.realpath}\" is not writable"
        end
      elsif !parent.directory?
        raise CliOptionError, "Error with --output-directory: the file \"#{@cli_options.output_directory}\" is not a directory"
      end
    end


    def check_actionwords_signature_file
      if cli_options.actionwords_diff?
        actionwords_signature_file = Pathname.new(cli_options.output_directory).join("actionwords_signature.yaml")
        if actionwords_signature_file.directory?
          raise CliOptionError, "Bad Action Words signature file: the file \"#{actionwords_signature_file.realpath}\" is a directory"
        elsif !actionwords_signature_file.exist?
          full_path = File.expand_path(cli_options.output_directory)
          raise CliOptionError, [
            "Missing Action Words signature file: the file \"actionwords_signature.yaml\" could not be found in directory \"#{full_path}\"",
            "Use --actionwords-signature to generate the file \"#{full_path}/actionwords_signature.yaml\"",
          ].join("\n")
        end
      end
    end

    def check_xml_file
      if cli_options.xml_file
        xml_path = clean_path(cli_options.xml_file)

        if !File.readable?(xml_path)
          raise CliOptionError, "Error with --xml-file: the file \"#{cli_options.xml_file}\" does not exist or is not readable"
        elsif !File.file?(xml_path)
          raise CliOptionError, "Error with --xml-file: the file \"#{cli_options.xml_file}\" is not a regular file"
        end
      end
    end

    def check_test_run_id
      if present?(cli_options.test_run_id) && !numeric?(cli_options.test_run_id)
        raise CliOptionError, "Invalid format --test-run-id=\"#{@cli_options.test_run_id}\": the test run id must be numeric"
      end
    end

    def check_language_and_only
      if present?(cli_options.language)
        begin
          language_config_parser = LanguageConfigParser.new(cli_options)
        rescue ArgumentError => err
          raise CliOptionError, err.message
        end

        if present?(cli_options.only)
          if language_config_parser.filtered_group_names != cli_options.groups_to_keep
            unknown_categories = cli_options.groups_to_keep - language_config_parser.group_names
            if unknown_categories.length == 1
              message = "the category #{formatted_categories(unknown_categories)} does not exist"
            else
              message = "the categories #{formatted_categories(unknown_categories)} do not exist"
            end
            raise CliOptionError, "Error with --only: #{message} for language #{cli_options.language_framework}. " +
              "Available categories are #{formatted_categories(language_config_parser.group_names)}."
          end
        end
      end
    end

    private

    def numeric?(arg)
      arg =~ /^\d*$/
    end

    def missing?(arg)
      arg.nil?
    end

    def empty?(arg)
      arg.strip.empty?
    end

    def absent?(arg)
      missing?(arg) || empty?(arg)
    end

    def present?(arg)
      !absent?(arg)
    end

    def formatted_categories(categories)
      formatted_categories = categories.map(&:inspect)
      if formatted_categories.length == 1
        formatted_categories.first
      else
        formatted_categories[0...-1].join(", ") + " and " + formatted_categories.last
      end
    end

    def first_existing_parent(path)
      pathname = Pathname.new(path)
      while !pathname.exist?
        pathname = pathname.parent
      end
      pathname.realpath
    end
  end
end
