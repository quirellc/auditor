require 'auditor/status'

module Auditor
  class Recorder
    include Status

    def initialize(options, &blk)
      @options = options
      @blk = blk
    end

    [:create, :find, :update, :destroy].each do |action|
      define_method("after_#{action}") do |model|
        audit(model, action)
      end
    end

  private

    def audit(model, action)
      return nil if auditing_disabled?
      user = Auditor::User.current_user

      audit = Audit.new
      audit.auditable_id = model.id
      audit.auditable_type = model.class.name
      audit.audited_changes = prepare_changes(changes_for_action(model, action))
      audit.action = action

      return if noop?(audit)

      audit.comment = @blk.call(model, user, action) if @blk

      without_auditing do
        owner = @options[:on] ? Array(@options[:on]).inject(model) { |owner, parent| owner.send(parent.to_sym) } : model
        audit.owner_id = owner.id
        audit.owner_type = owner.class.name
      end

      @options[:fail_on_error] ? audit.save! : audit.save
    end

    def changes_for_action(model, action)
      serialize_properties = @options["serialize_on_#{action}".to_sym]
      case action.to_s
      when 'destroy'
        return {} unless serialize_properties
        filter_changes(model, serialize_properties)
      else
        updated_attributes = if model.saved_changes?
          model.saved_changes
        else
          {}
        end
        updated_attributes.merge(filter_changes(model, serialize_properties))
      end
    end

    def filter_changes(model, desired_properties)
      return {} if desired_properties.blank?

      attributes = model.serializable_hash
      if desired_properties.is_a?(Array)
        attributes.keep_if { |key, value| desired_properties.include?(key.to_sym) }
      else
        attributes
      end
    end

    def prepare_changes(changes)
      chg = changes.dup
      chg = chg.delete_if { |key, value| @options[:except].include?(key) } unless @options[:except].blank?
      chg = chg.delete_if { |key, value| !@options[:only].include?(key) } unless @options[:only].blank?
      chg.empty? ? nil : chg
    end

    def noop?(audit)
      audit.action.to_s == 'update' && !audit.audited_changes.present? && !@options.key?(:serialize_on_update)
    end
  end
end
