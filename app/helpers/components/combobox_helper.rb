module Components::ComboboxHelper
  def render_combobox(**options, &block)
    content = capture(&block) if block
    render "components/ui/combobox", content: content, options: options
  end

  def combobox_trigger(&block)
    content_for :combobox_trigger, capture(&block), flush: true
  end

  def combobox_content(options = {}, &block)
    content_for :combobox_content_class, options[:class], flush: true
    content_for :combobox_content, capture(&block), flush: true
  end
end
