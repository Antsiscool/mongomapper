require 'spec_helper'

describe "Plugins" do
  it "should default plugins to empty array" do
    Class.new { extend MongoMapper::Plugins }.plugins.should == []
  end

  context "a plugin" do
    module MyConcern
      extend ActiveSupport::Concern

      included do
        attr_accessor :from_concern
      end

      module ClassMethods
        def class_foo
          'class_foo'
        end
      end

      def instance_foo
        'instance_foo'
      end
    end

    before do
      @document = Class.new do
        extend MongoMapper::Plugins
        plugin MyConcern
      end
    end

    it "should include instance methods" do
      @document.new.instance_foo.should == 'instance_foo'
    end

    it "should extend class methods" do
      @document.class_foo.should == 'class_foo'
    end

    it "should pass model to configure" do
      @document.new.should respond_to(:from_concern)
    end

    it "should add plugin to plugins" do
      @document.plugins.should include(MyConcern)
    end

    context "Document" do
      before do
        MongoMapper::Document.plugins.delete(MyConcern)
      end

      it 'should allow plugins on Document' do
        MongoMapper::Document.plugin(MyConcern)
        Doc().should respond_to(:class_foo)
        Doc().new.should respond_to(:instance_foo)
      end

      it 'should add plugins to classes that include Document before they are added' do
        article = Doc()
        MongoMapper::Document.plugin(MyConcern)
        article.should respond_to(:class_foo)
        article.new.should respond_to(:instance_foo)
      end
    end

    context "descendants and garbage collection" do
      # Built in a separate method so no references stay on the stack
      def discarded_classes(count, &block)
        Array.new(count) { WeakRef.new(block.call) }
      end

      def collect_garbage
        4.times { GC.start(full_mark: true, immediate_sweep: true) }
      end

      def reload_model
        Object.send(:remove_const, :PluginsReloadModel) if defined?(::PluginsReloadModel)
        Object.class_eval <<-RUBY
          class PluginsReloadModel; include MongoMapper::Document; end
          class PluginsReloadModel::Child < PluginsReloadModel; end
        RUBY
        PluginsReloadModel
      end

      after do
        Object.send(:remove_const, :PluginsReloadModel) if defined?(::PluginsReloadModel)
      end

      it "should not keep discarded Document classes alive" do
        refs = discarded_classes(20) { Class.new { include MongoMapper::Document } }
        collect_garbage
        refs.count(&:weakref_alive?).should < 5
      end

      it "should not keep discarded subclasses alive" do
        parent = Doc()
        refs = discarded_classes(20) { Class.new(parent) }
        collect_garbage
        refs.count(&:weakref_alive?).should < 5
        parent.direct_descendants.to_a.size.should < 5
      end

      it "should not keep reloaded classes alive" do
        refs = discarded_classes(20) { reload_model }
        current = reload_model
        collect_garbage
        refs.count(&:weakref_alive?).should < 5
        current.direct_descendants.to_a.should == [PluginsReloadModel::Child]
        MongoMapper::Document.direct_descendants.to_a.should include(current)
      end

      it "should still add plugins to classes that are alive" do
        model = reload_model
        collect_garbage
        MongoMapper::Document.plugin(MyConcern)
        model.should respond_to(:class_foo)
        model::Child.new.should respond_to(:instance_foo)
        MongoMapper::Document.plugins.delete(MyConcern)
      end
    end

    context "EmbeddedDocument" do
      before do
        MongoMapper::EmbeddedDocument.plugins.delete(MyConcern)
      end

      it 'should allow plugins on EmbeddedDocument' do
        MongoMapper::EmbeddedDocument.plugin(MyConcern)
        article = EDoc()
        article.should respond_to(:class_foo)
        article.new.should respond_to(:instance_foo)
      end

      it 'should add plugins to classes that include EmbeddedDocument before they are added' do
        article = EDoc()
        MongoMapper::EmbeddedDocument.plugin(MyConcern)
        article.should respond_to(:class_foo)
        article.new.should respond_to(:instance_foo)
      end
    end
  end
end