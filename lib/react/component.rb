require 'react/ext/string'
require 'react/ext/hash'
require 'active_support/core_ext/class/attribute'
require 'react/callbacks'
require 'react/rendering_context'
require 'react/observable'
require 'react/state'
require 'react/component/api'
require 'react/component/class_methods'
require 'react/component/props_wrapper'
require 'native'

module React
  module Component
    def self.included(base)
      base.include(API)
      base.include(Callbacks)
      base.include(Tags)
      base.include(DslInstanceMethods)
      base.class_eval do
        class_attribute :initial_state
        define_callback :before_mount
        define_callback :after_mount
        define_callback :before_receive_props
        define_callback :before_update
        define_callback :after_update
        define_callback :before_unmount
      end
      base.extend(ClassMethods)
    end

    def self.deprecation_warning(message)
      @deprecation_messages ||= []
      message = "Warning: Deprecated feature used in #{name}. #{message}"
      unless @deprecation_messages.include? message
        @deprecation_messages << message
        IsomorphicHelpers.log message, :warning
      end
    end

    def initialize(native_element)
      @native = native_element
    end

    def render
      raise 'no render defined'
    end unless method_defined?(:render)

    def update_react_js_state(object, name, value)
      return if @rendering_now
      if object
        name = "#{object.class}.#{name}" unless object == self
        set_state(
          '***_state_updated_at-***' => Time.now.to_f,
          name => value
        )
      else
        set_state name => value
      end
    end

    def emit(event_name, *args)
      self.params["_on#{event_name.to_s.event_camelize}"].call(*args)
    end

    def component_will_mount
      IsomorphicHelpers.load_context(true) if IsomorphicHelpers.on_opal_client?
      @props_wrapper = self.class.props_wrapper.new(Hash.new(`#{@native}.props`))
      set_state! initial_state if initial_state
      State.initialize_states(self, initial_state)
      State.set_state_context_to(self) { self.run_callback(:before_mount) }
    rescue Exception => e
      self.class.process_exception(e, self)
    end

    def component_did_mount
      State.set_state_context_to(self) do
        self.run_callback(:after_mount)
        State.update_states_to_observe
      end
    rescue Exception => e
      self.class.process_exception(e, self)
    end

    def component_will_receive_props(next_props)
      # need to rethink how this works in opal-react, or if its actually that useful within the react.rb environment
      # for now we are just using it to clear processed_params
      State.set_state_context_to(self) { self.run_callback(:before_receive_props, Hash.new(next_props)) }
    rescue Exception => e
      self.class.process_exception(e, self)
    end

    def should_component_update?(native_next_props, native_next_state)
      State.set_state_context_to(self) do
        next_params = Hash.new(native_next_props)
        if respond_to?(:needs_update?)
          call_needs_update(next_params, native_next_state)
        else
          !!(props_changed?(next_params) || native_state_changed?(native_next_state))
        end.to_n
      end
    end

    def call_needs_update(next_params, native_next_state)
      component = self
      next_params.define_singleton_method(:changed?) do
        @changing ||= component.props_changed?(self)
      end
      next_state = Hash.new(native_next_state)
      next_state.define_singleton_method(:changed?) do
        @changing ||= component.native_state_changed?(native_next_state)
      end
      !!needs_update?(next_params, next_state)
    end

    def native_state_changed?(next_state)
      %x{
        var normalized_next_state =
          (!#{next_state} || Object.keys(#{next_state}).length === 0 || #{nil} == next_state) ? false : #{next_state}
        var normalized_current_state =
          (!#{@native}.state || Object.keys(#{@native}.state).length === 0 || #{nil} == #{@native}.state) ? false : #{@native}.state
        if (!normalized_current_state != !normalized_next_state) return(true)
        if (!normalized_current_state && !normalized_next_state) return(false)
        if (!normalized_current_state['***_state_updated_at-***'] ||
            !normalized_next_state['***_state_updated_at-***']) return(true)
        return (normalized_current_state['***_state_updated_at-***'] !=
                normalized_next_state['***_state_updated_at-***'])
      }
    end

    def props_changed?(next_params)
      (props.keys.sort != next_params.keys.sort) ||
        next_params.detect { |k, _v| `#{next_params[k]} != #{@native}.props[#{k}]` }
    end

    def component_will_update(next_props, next_state)
      State.set_state_context_to(self) { self.run_callback(:before_update, Hash.new(next_props), Hash.new(next_state)) }
      @props_wrapper = self.class.props_wrapper.new(Hash.new(next_props), @props_wrapper)
    rescue Exception => e
      self.class.process_exception(e, self)
    end

    def component_did_update(prev_props, prev_state)
      State.set_state_context_to(self) do
        self.run_callback(:after_update, Hash.new(prev_props), Hash.new(prev_state))
        State.update_states_to_observe
      end
    rescue Exception => e
      self.class.process_exception(e, self)
    end

    def component_will_unmount
      State.set_state_context_to(self) do
        self.run_callback(:before_unmount)
        State.remove
      end
    rescue Exception => e
      self.class.process_exception(e, self)
    end

    attr_reader :waiting_on_resources

    def _render_wrapper
      @rendering_now = true
      State.set_state_context_to(self) do
        React::RenderingContext.render(nil) {render || ""}.tap { |element| @waiting_on_resources = element.waiting_on_resources if element.respond_to? :waiting_on_resources }
      end
    rescue Exception => e
      self.class.process_exception(e, self)
    ensure
      @rendering_now = false
    end

    def watch(value, &on_change)
      Observable.new(value, on_change)
    end

    def define_state(*args, &block)
      State.initialize_states(self, self.class.define_state(*args, &block))
    end

  end
end
