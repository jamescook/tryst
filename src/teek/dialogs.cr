module Teek
  # Native OS dialog wrappers - reopens App directly (mirrors ruby-teek's
  # own file layout: lib/teek/dialogs.rb reopens class App rather than
  # defining a separate wrapper class, unlike Winfo/Clipboard/Window).
  class App
    # Show the native "choose file to open" dialog. filetypes: e.g.
    # [{"PNG Images", ".png"}, {"All Files", "*"}] - the second element of
    # each pair can also be an array of extensions
    # ({"Images", [".png", ".jpg"]}). multiple: allow selecting more than
    # one file. Returns the chosen path (an array of paths if multiple:),
    # or nil if the dialog was cancelled.
    def choose_open_file(filetypes = nil, initialdir : String? = nil, initialfile : String? = nil,
                         title : String? = nil, multiple : Bool = false, parent = nil) : (String | Array(String))?
      args = ["tk_getOpenFile"]
      args.push("-filetypes", build_filetypes(filetypes)) if filetypes
      args.push("-initialdir", initialdir) if initialdir
      args.push("-initialfile", initialfile) if initialfile
      args.push("-title", title) if title
      args.push("-parent", parent.to_s) if parent
      args.push("-multiple", bool_to_tcl(true)) if multiple

      result = tcl_invoke(args)
      return if result.empty?

      multiple ? split_list(result) : result
    end

    # Show the native "choose file to save" dialog. filetypes: see
    # #choose_open_file. defaultextension: appended if the typed filename
    # doesn't already have one. confirmoverwrite: ask before overwriting
    # an existing file (Tk's own default is true; pass false to skip the
    # confirmation). Returns the chosen path, or nil if cancelled.
    def choose_save_file(filetypes = nil, initialdir : String? = nil, initialfile : String? = nil,
                         title : String? = nil, defaultextension : String? = nil,
                         confirmoverwrite : Bool = true, parent = nil) : String?
      args = ["tk_getSaveFile"]
      args.push("-filetypes", build_filetypes(filetypes)) if filetypes
      args.push("-initialdir", initialdir) if initialdir
      args.push("-initialfile", initialfile) if initialfile
      args.push("-title", title) if title
      args.push("-defaultextension", defaultextension) if defaultextension
      args.push("-confirmoverwrite", bool_to_tcl(false)) unless confirmoverwrite
      args.push("-parent", parent.to_s) if parent

      result = tcl_invoke(args)
      result.empty? ? nil : result
    end

    # Show a message box with one or more buttons. icon:
    # :error/:info/:question/:warning. type:
    # :ok/:okcancel/:abortretryignore/:yesno/:yesnocancel/:retrycancel -
    # which button(s) to show. default: which button is focused by
    # default (e.g. :cancel); Tk's own choice if omitted. Returns the
    # pressed button as a Symbol - :ok, :cancel, :yes, :no, :abort,
    # :retry, or :ignore.
    def message_box(message : String, title : String? = nil, detail : String? = nil,
                    icon : Symbol = :info, type : Symbol = :ok,
                    default : Symbol? = nil, parent = nil) : Symbol
      args = ["tk_messageBox", "-message", message]
      args.push("-title", title) if title
      args.push("-detail", detail) if detail
      args.push("-icon", icon.to_s)
      args.push("-type", type.to_s)
      args.push("-default", default.to_s) if default
      args.push("-parent", parent.to_s) if parent

      # Crystal's Symbol set is fixed at compile time (no general
      # String#to_sym like Ruby's - an arbitrary runtime string can't
      # become a new Symbol), so the button name Tk returns needs an
      # explicit mapping rather than a direct conversion.
      result = tcl_invoke(args)
      case result
      when "ok"     then :ok
      when "cancel" then :cancel
      when "yes"    then :yes
      when "no"     then :no
      when "abort"  then :abort
      when "retry"  then :retry
      when "ignore" then :ignore
      else
        raise TclError.new("unexpected tk_messageBox result: #{result.inspect}")
      end
    end

    # Show the native color picker dialog. initial: e.g. "#ff0000".
    # Returns the chosen color as "#rrggbb", or nil if cancelled.
    def choose_color(initial : String? = nil, title : String? = nil, parent = nil) : String?
      args = ["tk_chooseColor"]
      args.push("-initialcolor", initial) if initial
      args.push("-title", title) if title
      args.push("-parent", parent.to_s) if parent

      result = tcl_invoke(args)
      result.empty? ? nil : result
    end

    # Show the native "choose directory" dialog. mustexist: restrict the
    # choice to an already-existing directory (Tk's own default is false,
    # allowing a not-yet-created one). Returns the chosen directory path,
    # or nil if cancelled.
    def choose_dir(initialdir : String? = nil, mustexist : Bool = false,
                   title : String? = nil, parent = nil) : String?
      args = ["tk_chooseDirectory"]
      args.push("-initialdir", initialdir) if initialdir
      args.push("-mustexist", bool_to_tcl(true)) if mustexist
      args.push("-title", title) if title
      args.push("-parent", parent.to_s) if parent

      result = tcl_invoke(args)
      result.empty? ? nil : result
    end

    # Pop up a menu at the given screen coordinates. menu: a Widget or
    # path String. entry: index or label of the entry to show as active.
    def popup_menu(menu, x : Int32, y : Int32, entry = nil) : Nil
      args = ["tk_popup", menu.to_s, x.to_s, y.to_s]
      args << entry.to_s if entry
      tcl_invoke(args)
    end

    # Builds the nested Tcl list -filetypes expects:
    # {{name extensionOrExtensionList} {name2 ...}}
    private def build_filetypes(filetypes) : String
      entries = filetypes.map do |name, exts|
        ext_arg = exts.is_a?(Array) ? make_list(exts.map(&.to_s)) : exts.to_s
        make_list([name.to_s, ext_arg])
      end
      make_list(entries)
    end
  end
end
