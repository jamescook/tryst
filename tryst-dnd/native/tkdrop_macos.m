/* tkdrop_macos.m - macOS file drop target via Cocoa NSDraggingDestination
 *
 * Based on tkdnd (https://github.com/petasis/tkdnd) as protocol
 * reference. MIT license, matching the rest of this project.
 *
 * The NSView/NSDraggingDestination conformance below is entirely
 * internal Objective-C, compiled by clang the same as any other .m
 * file - nothing outside this file ever needs to know it's there. The
 * one thing anything outside this file calls is the plain C entry
 * point at the bottom, teek_register_drop_target, which is what makes
 * this callable from a language with no ObjC runtime support of its
 * own (Crystal FFI just sees one ordinary C function).
 */

#import <Cocoa/Cocoa.h>
#include <tcl.h>
#include <tk.h>
#include "tkdrop.h"

#ifndef MAC_OSX_TK
#define MAC_OSX_TK
#endif
/* tkMacOSX.h declares the Tk_MacOSXEmbed*Proc typedefs tkPlatDecls.h's
 * own declarations reference - confirmed directly against a real
 * Homebrew tcl-tk@8 install: without this, tkPlatDecls.h alone fails
 * to compile ("unknown type name 'Tk_MacOSXEmbedRegisterWinProc'"). */
#include "tkMacOSX.h"
#include "tkPlatDecls.h"
#if TCL_MAJOR_VERSION < 9
/* TkMacOSXDrawable's own real prototype (tkIntPlatDecls.h:259, exactly
 * as declared there: `EXTERN void * TkMacOSXDrawable(Drawable
 * drawable);`) - see teek_register_drop_target's own comment on why
 * 8.6 needs this Tk-internal function instead of the public 9.x-only
 * Tk_MacOSXGetNSWindowForDrawable. Declared directly rather than
 * #include-ing tkIntPlatDecls.h itself: that header's OTHER
 * declarations reference genuinely private Tk-internal types (TkWindow,
 * TkRegion, MacDrawable) that need Tk's own private build headers,
 * which Homebrew's public tcl-tk@8 package doesn't ship - confirmed
 * directly, including it wholesale fails with "unknown type name
 * 'TkWindow'". This one function's own signature only uses the public
 * Drawable type, so a standalone forward declaration is all that's
 * actually needed. */
extern void *TkMacOSXDrawable(Drawable drawable);
#endif

/* --------------------------------------------------------- */

@interface TeekDropView : NSView <NSDraggingDestination>
{
    Tcl_Interp *_interp;
    char *_widgetPath;
}
- (instancetype)initWithFrame:(NSRect)frame
                       interp:(Tcl_Interp *)interp
                   widgetPath:(const char *)widgetPath;
@end

@implementation TeekDropView

- (instancetype)initWithFrame:(NSRect)frame
                       interp:(Tcl_Interp *)interp
                   widgetPath:(const char *)widgetPath
{
    self = [super initWithFrame:frame];
    if (self) {
        _interp = interp;
        _widgetPath = strdup(widgetPath);
        [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (void)dealloc
{
    free(_widgetPath);
    [super dealloc];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pb = [sender draggingPasteboard];
    if ([pb canReadObjectForClasses:@[[NSURL class]]
                            options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls || [urls count] == 0) {
        return NO;
    }

    /* Build a Tcl list of all dropped file paths */
    Tcl_Obj *listObj = Tcl_NewListObj(0, NULL);
    Tcl_IncrRefCount(listObj);

    for (NSURL *url in urls) {
        NSString *path = [url path];
        if (!path) continue;
        Tcl_ListObjAppendElement(NULL, listObj,
            Tcl_NewStringObj([path UTF8String], -1));
    }

    /* Generate single <<DropFile>> event with all paths as a Tcl list */
    Tcl_Obj *script = Tcl_ObjPrintf(
        "event generate %s <<DropFile>> -data {%s}",
        _widgetPath, Tcl_GetString(listObj));
    Tcl_IncrRefCount(script);
    Tcl_EvalObjEx(_interp, script, TCL_EVAL_GLOBAL);
    Tcl_DecrRefCount(script);
    Tcl_DecrRefCount(listObj);

    return YES;
}

/* Allow the drop view to be transparent to mouse events when not dragging */
- (NSView *)hitTest:(NSPoint)point
{
    return nil;
}

@end

/* --------------------------------------------------------- */

int
teek_register_drop_target(Tcl_Interp *interp, Tk_Window tkwin,
                          const char *widget_path)
{
    Drawable drawable = Tk_WindowId(tkwin);
    if (!drawable) {
        Tcl_SetResult(interp, "window has no native handle", TCL_STATIC);
        return TCL_ERROR;
    }

    /* Tk_MacOSXGetNSWindowForDrawable is a real EXPORTED symbol only on
     * Tk 9.x - confirmed directly (linking against 8.6 fails with
     * "symbol not found"). 8.6 has the same functionality under a
     * different, Tk-internal name, TkMacOSXDrawable (tkIntPlatDecls.h)
     * - the exact same version split core tryst's own
     * native_window_handle code already handles on the Crystal FFI
     * side (see Tryst::TCL_MAJOR_VERSION's own doc comment there);
     * TCL_MAJOR_VERSION here is tcl.h's own real preprocessor macro,
     * so this tracks whichever headers the Makefile actually compiled
     * against, not a separately-invented flag. */
#if TCL_MAJOR_VERSION >= 9
    void *nswindow = Tk_MacOSXGetNSWindowForDrawable(drawable);
#else
    void *nswindow = TkMacOSXDrawable(drawable);
#endif
    if (!nswindow) {
        Tcl_SetResult(interp, "could not get NSWindow", TCL_STATIC);
        return TCL_ERROR;
    }

    NSWindow *window = (__bridge NSWindow *)nswindow;
    NSView *contentView = [window contentView];
    if (!contentView) {
        Tcl_SetResult(interp, "could not get content view", TCL_STATIC);
        return TCL_ERROR;
    }

    /* Check if we already registered a drop view on this window */
    for (NSView *subview in [contentView subviews]) {
        if ([subview isKindOfClass:[TeekDropView class]]) {
            return TCL_OK; /* Already registered */
        }
    }

    TeekDropView *dropView = [[TeekDropView alloc]
        initWithFrame:[contentView bounds]
               interp:interp
           widgetPath:widget_path];

    [contentView addSubview:dropView];

    return TCL_OK;
}
