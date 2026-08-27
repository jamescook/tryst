module Tryst
  module UI
    # A named ttk style handle, returned by WidgetDSL#style's named form -
    # what to pass as a widget's style: instead of the raw "Prefix.TButton"
    # ttk spelling. #to_s is the raw name, so a StyleRef and a plain String
    # are interchangeable wherever style: is accepted.
    record StyleRef, ttk_name : String do
      def to_s(io : IO) : Nil
        io << ttk_name
      end
    end

    # The DSL widget vocabulary's ttk widget-class names - what #style's
    # type: argument maps to before a name: prefix is folded in. One place,
    # exhaustive over every DSL type ttk actually themes; anything else
    # (canvas, list, text_area, window - no ttk class of their own) has no
    # entry and #for raises rather than guessing.
    module TtkStyleNames
      WIDGET_CLASSES = {
        :button   => "TButton",
        :label    => "TLabel",
        :text_box => "TEntry",
        :checkbox => "TCheckbutton",
        :radio    => "TRadiobutton",
        :dropdown => "TCombobox",
        :slider   => "TScale",
        :progress => "TProgressbar",
        :panel    => "TFrame",
        :group    => "TLabelframe",
        :tabs     => "TNotebook",
        :tree     => "Treeview",
        :table    => "Treeview",
        :split    => "TPanedwindow",
      } of Symbol => String

      def self.for(type : Symbol) : String
        WIDGET_CLASSES[type]? || raise ArgumentError.new(
          "ui.style doesn't know a ttk class for :#{type} - known types: " \
          "#{WIDGET_CLASSES.keys.join(", ")}")
      end
    end
  end
end
