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

    # Whether a class is actually GC'd depends on the Ruby / Rails version and platform,
    # so these check that MongoMapper only ever holds weak references instead
    context "descendants" do
      def stored_refs(owner)
        list = owner.instance_variable_get(:@direct_descendants)
        list ? list.instance_variable_get(:@refs) : []
      end

      it "should hold classes that include Document as weak references" do
        model = Doc()
        MongoMapper::Document.direct_descendants.to_a.should include(model)
        stored_refs(MongoMapper::Document).should_not be_empty
        stored_refs(MongoMapper::Document).each { |ref| ref.should be_a(WeakRef) }
      end

      it "should hold subclasses as weak references, or not at all when Ruby tracks them" do
        parent = Doc()
        child = Class.new(parent)
        parent.direct_descendants.to_a.should == [child]
        stored_refs(parent).each { |ref| ref.should be_a(WeakRef) }
        stored_refs(parent).should be_empty if MongoMapper::Plugins::NATIVE_SUBCLASSES
      end

      it "should not keep a global registry of classes" do
        Class.new(Doc())
        MongoMapper::Plugins.instance_variables.should be_empty
      end

      it "should skip and drop classes that have been garbage collected" do
        collected = Object.new
        def collected.__getobj__
          raise WeakRef::RefError
        end

        model = Doc()
        list = MongoMapper::Plugins::DescendantsArray.new
        list << model
        list.instance_variable_get(:@refs).unshift(collected)

        list.to_a.should == [model]
        list.instance_variable_get(:@refs).size.should == 1
      end

      it "should add plugins to existing subclasses" do
        child = Class.new(Doc())
        MongoMapper::Document.plugin(MyConcern)
        child.should respond_to(:class_foo)
        child.new.should respond_to(:instance_foo)
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