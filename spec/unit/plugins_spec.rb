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

    context "descendants" do
      it "should track classes that include Document and their subclasses" do
        parent = Doc()
        child = Class.new(parent)
        MongoMapper::Document.direct_descendants.to_a.should include(parent)
        parent.direct_descendants.to_a.should == [child]
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

    # Whether a class is actually GC'd depends on the Ruby / Rails version and platform,
    # so instead check nothing MongoMapper holds can strongly reach it
    context "descendants and garbage collection" do
      before do
        skip "ObjectSpace.reachable_objects_from is MRI only" unless RUBY_ENGINE == "ruby"
        require 'objspace'
      end

      def strongly_held?(target, *owners)
        roots = [MongoMapper::Plugins, MongoMapper::Document, MongoMapper::EmbeddedDocument] + owners
        queue = roots.flat_map do |mod|
          mod.instance_variables.map { |name| mod.instance_variable_get(name) } +
            mod.class_variables.map { |name| mod.class_variable_get(name) } +
            mod.constants(false).map { |name| mod.const_get(name) }.reject { |c| c.is_a?(Module) }
        end
        seen = {}.compare_by_identity

        until queue.empty?
          obj = queue.shift
          return true if obj.equal?(target)
          # Thread and fiber stacks include this spec's own local variables
          next if seen[obj] || obj.is_a?(Module) || obj.is_a?(Thread) || obj.is_a?(Fiber)
          seen[obj] = true
          # Internal objects come back as fresh wrappers each time, and can't be walked
          refs = ObjectSpace.reachable_objects_from(obj) || []
          queue.concat(refs.reject { |ref| ref.is_a?(ObjectSpace::InternalObjectWrapper) })
        end
        false
      end

      it "should detect a strong reference" do
        model = Doc()
        MongoMapper::Document.instance_variable_set(:@strong_ref_probe, [model])
        begin
          strongly_held?(model).should be_truthy
        ensure
          MongoMapper::Document.send(:remove_instance_variable, :@strong_ref_probe)
        end
      end

      it "should not strongly hold classes that include Document" do
        model = Doc()
        MongoMapper::Document.direct_descendants.to_a.should include(model)
        strongly_held?(model).should be_falsey
      end

      it "should not strongly hold classes that include EmbeddedDocument" do
        model = EDoc()
        MongoMapper::EmbeddedDocument.direct_descendants.to_a.should include(model)
        strongly_held?(model).should be_falsey
      end

      it "should not strongly hold subclasses" do
        parent = Doc()
        child = Class.new(parent)
        parent.direct_descendants.to_a.should == [child]
        strongly_held?(child, parent).should be_falsey
      end

      it "should not strongly hold classes removed by code reloading" do
        Object.class_eval "class PluginsReloadModel; include MongoMapper::Document; end"
        old = PluginsReloadModel
        Object.send(:remove_const, :PluginsReloadModel)
        strongly_held?(old).should be_falsey
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