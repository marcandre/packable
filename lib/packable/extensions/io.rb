require 'enumerator'
Enumerator = Enumerable::Enumerator unless defined?(Enumerator)

module Packable
  module Extensions #:nodoc:
    module IO
      def self.included(base) #:nodoc:
        base.__send__(:alias_method, :read_without_packing, :read)
        base.__send__(:alias_method, :read, :read_with_packing)
        base.__send__(:alias_method, :write_without_packing, :write)
        base.__send__(:alias_method, :write, :write_with_packing)
        base.__send__(:alias_method, :each_without_packing, :each)
        base.__send__(:alias_method, :each, :each_with_packing)
      end

      # Methods supported by seekable streams.
      SEEKABLE_API = %i[pos pos= seek rewind].freeze

      # Check whether can seek without errors.
      def seekable?
        if !defined?(@seekable)
          @seekable =
            # The IO class throws an exception at runtime if we try to change
            # position on a non-regular file.
            if respond_to?(:stat)
              stat.file?
            else
              # Duck-type the rest of this.
              SEEKABLE_API.all? { |m| respond_to?(m) }
            end
        end
        @seekable
      end

      # Returns the change in io.pos caused by the block.
      # Has nothing to do with packing, but quite helpful and so simple...
      def pos_change(&block)
        delta =- pos
        yield
        delta += pos
      end

      # Usage:
      #   io >> Class
      #   io >> [Class, options]
      #   io >> :shortcut
      def >> (options)
        r = []
        class << r
          attr_accessor :stream
          def >> (options)
            self << stream.read(options)
          end
        end
        r.stream = self
        r >> options
      end

      # Returns (or yields) a modified IO object that will always pack/unpack when writing/reading.
      def packed
        packedio = clone
        packedio.set_encoding("ascii-8bit") if packedio.respond_to? :set_encoding
        class << packedio
          def << (arg)
            arg = [arg, :default] unless arg.instance_of?(::Array)
            pack_and_write(*arg)
            self
          end
          def packed
            block_given? ? yield(self) : self
          end
          alias_method :write, :pack_and_write #bypass test for argument length
        end
        block_given? ? yield(packedio) : packedio
      end

      def each_with_packing(*options, &block)
        return each_without_packing(*options, &block) if options.empty? || (Integer === options.first) || (String === options.first) || !seekable?
        return self.to_enum(__method__, *options) unless block_given?
        yield read(*options) until eof?
      end

      def write_with_packing(*arg)
        (arg.length <= 1 || !seekable?) ? write_without_packing(*arg) : pack_and_write(*arg)
      end

      def read_with_packing(*arg)
        return read_without_packing(*arg) if arg.empty? || arg.first.nil? || arg.first.is_a?(Numeric) || !seekable?
        values = Packable::Packers.to_class_option_list(*arg).map do |klass, options, original|
          if options[:read_packed]
            options[:read_packed].call(self)
          else
            klass.read_packed(self, options)
          end
        end
        return values.size > 1 ? values : values.first
      end

      # returns a string of exactly n bytes, or else raises an EOFError
      def read_exactly(n)
        return "" if n.zero?
        s = read_without_packing(n)
        raise EOFError if s.nil? || s.length < n
        s
      end

      def pack_and_write(*arg)
        original_pos = pos
        Packable::Packers.to_object_option_list(*arg).each do |obj, options|
          if options[:write_packed]
            options[:write_packed].bind(obj).call(self)
          else
            obj.write_packed(self, options)
          end
        end
        pos - original_pos
      end

    end
  end
end
