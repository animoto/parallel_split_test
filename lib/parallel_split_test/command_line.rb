require 'parallel_split_test'
require 'parallel_split_test/output_recorder'
require 'parallel'
require 'rspec'
require 'parallel_split_test/core_ext/rspec_example'

module ParallelSplitTest
  class CommandLine < RSpec::Core::CommandLine
    def initialize(args)
      @args = args

      delete_next = false
      @concurrency = nil
      @args.delete_if do |arg|
        if delete_next
          @concurrency = arg.to_i
          true
        elsif arg == '--parallel-test'
          delete_next = true
          true
        end
      end

      super
    end

    def run(err, out)
      processes = ParallelSplitTest.choose_number_of_processes(@concurrency)
      out.puts "Running examples in #{processes} processes"

      results = Parallel.in_processes(processes) do |process_number|
        ParallelSplitTest.example_counter = 0
        ParallelSplitTest.process_number = process_number
        set_test_env_number(process_number)
        #modify_out_file_in_args(process_number) if out_file

        out = OutputRecorder.new(out)
        setup_copied_from_rspec(err, out)
        [run_group_of_tests, out.recorded]
      end

      #combine_out_files if out_file
      unless results.nil?
        reprint_result_lines(out, results.map(&:last))
        results.map(&:first).max # combine exit status
      end
    end

    private

    # modify + reparse args to unify output
    def modify_out_file_in_args(process_number)
      @args[out_file_position] = "#{out_file}.#{process_number}"
      @options = RSpec::Core::ConfigurationOptions.new(@args)
      @options.parse_options
    end

    def set_test_env_number(process_number)
      ENV['TEST_ENV_NUMBER'] = process_number.to_s
    end

    def out_file
      @out_file ||= @args[out_file_position] if out_file_position
    end

    def out_file_position
      @out_file_position ||= begin
        if out_position = @args.index { |i| ["-o", "--out"].include?(i) }
          out_position + 1
        end
      end
    end

    def combine_out_files
      File.open(out_file, "w") do |f|
        Dir["#{out_file}.*"].each do |file|
          f.write File.read(file)
          File.delete(file)
        end
      end
    end

    def reprint_result_lines(out, printed_outputs)
      out.puts
      out.puts "Summary:"
      out.puts printed_outputs.map{|o| o[/.*\d+ failure.*/] }.join("\n")
    end

    def run_group_of_tests
      example_count = @world.example_count / ParallelSplitTest.processes

      if ParallelSplitTest.process_number < @world.example_count
        @configuration.reporter.report(example_count, seed) do |reporter|
          begin
            @configuration.run_hook(:before, :suite)
            groups = @world.example_groups.ordered
            results = groups.map {|g| g.run(reporter)}
            results.all? ? 0 : @configuration.failure_exit_code
          ensure
            @configuration.run_hook(:after, :suite)
          end
        end
      else
        results = 0
      end
    end

    def seed
      @configuration.randomize? ? @configuration.seed : nil
    end

    def setup_copied_from_rspec(err, out)
      @configuration.error_stream = err
      @configuration.output_stream ||= out
      @options.configure(@configuration)
      @configuration.load_spec_files
      @world.announce_filters
    end
  end
end
