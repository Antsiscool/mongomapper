# encoding: UTF-8
require 'weakref'

module MongoMapper
  module Plugins
    # Ruby 3.1+ tracks subclasses natively (and weakly)
    NATIVE_SUBCLASSES = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.1')

    # Holds weak references so classes dropped by code reloading can be GC'd
    class DescendantsArray
      include Enumerable

      def initialize
        @refs = []
      end

      def <<(klass)
        @refs << WeakRef.new(klass)
        self
      end

      def each
        @refs.reject! do |ref|
          begin
            yield ref.__getobj__
            false
          rescue WeakRef::RefError
            true
          end
        end
        self
      end
    end

    def plugins
      @plugins ||= []
    end

    def plugin(mod)
      raise ArgumentError,  "Plugins must extend ActiveSupport::Concern" unless ActiveSupport::Concern === mod
      include mod
      direct_descendants.each {|model| model.send(:include, mod) }
      plugins << mod
    end

    def direct_descendants
      return subclasses if NATIVE_SUBCLASSES && is_a?(Class)
      @direct_descendants ||= DescendantsArray.new
    end

    def included(base = nil)
      direct_descendants << base if base
      super
    end

    def inherited(subclass)
      direct_descendants << subclass unless NATIVE_SUBCLASSES
      super
    end
  end
end
