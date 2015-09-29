require 'parallel'

module ParallelSplitTest
  class << self
    attr_accessor :example_counter, :processes, :process_number

    def run_example?
      self.example_counter += 1
      (example_counter - 1) % processes == process_number
    end

    def choose_number_of_processes(concurrency)
      self.processes = concurrency
    end
  end
end
