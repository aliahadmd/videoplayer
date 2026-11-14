import AppKit
import SwiftUI
import OpenGL.GL3
import CMPV
import PlayerCore

nonisolated final class GLRenderer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.liplayer.render", qos: .userInteractive)
    private let context: CGLContextObj
    private var render: OpaquePointer?
    private var width: Int32 = 1
    private var height: Int32 = 1
    private var retainedContext: UnsafeMutableRawPointer?

    init(engine: PlaybackEngine, context: CGLContextObj) throws {
        self.context = context
        var failure: Int32 = 0
        queue.sync {
            CGLLockContext(context); defer { CGLUnlockContext(context) }
            CGLSetCurrentContext(context)
            var initParams = mpv_opengl_init_params(get_proc_address: { _, name in
                guard let name else { return nil }
                return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
            }, get_proc_address_ctx: nil)
            "opengl".withCString { api in
                withUnsafeMutablePointer(to: &initParams) { gl in
                    var params = [mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: api)), mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: gl), mpv_render_param()]
                    failure = mpv_render_context_create(&render, engine.handle, &params)
                }
            }
        }
        guard failure >= 0 else { throw EngineError.message("Could not initialize video rendering: \(String(cString: mpv_error_string(failure)))") }
        retainedContext = Unmanaged.passRetained(self).toOpaque()
        mpv_render_context_set_update_callback(render, { pointer in
            guard let pointer else { return }
            Unmanaged<GLRenderer>.fromOpaque(pointer).takeUnretainedValue().draw()
        }, retainedContext)
    }
    func resize(width: Int32, height: Int32) {
        queue.async { [self] in self.width = max(1, width); self.height = max(1, height); renderFrame() }
    }
    func draw() { queue.async { [self] in renderFrame() } }
    private func renderFrame() {
        guard let render else { return }
        CGLLockContext(context); defer { CGLUnlockContext(context) }
        CGLSetCurrentContext(context)
        _ = mpv_render_context_update(render)
        var fbo = mpv_opengl_fbo(fbo: 0, w: width, h: height, internal_format: 0)
        var flip: Int32 = 1
        var block: Int32 = 0
        withUnsafeMutablePointer(to: &fbo) { target in
            withUnsafeMutablePointer(to: &flip) { flipPointer in
                withUnsafeMutablePointer(to: &block) { blockPointer in
                    var params = [mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: target), mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPointer), mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: blockPointer), mpv_render_param()]
                    mpv_render_context_render(render, &params)
                }
            }
        }
        CGLFlushDrawable(context)
        mpv_render_context_report_swap(render)
    }
    func stop() {
        queue.sync {
            guard let render else { return }
            CGLLockContext(context); defer { CGLUnlockContext(context) }
            CGLSetCurrentContext(context)
            mpv_render_context_set_update_callback(render, nil, nil)
            mpv_render_context_free(render)
            self.render = nil
        }
        if let pointer = retainedContext { retainedContext = nil; Unmanaged<GLRenderer>.fromOpaque(pointer).release() }
    }
}

final class VideoOpenGLView: NSOpenGLView {
    let session: PlayerSession
    var renderer: GLRenderer?
    init?(session: PlayerSession) {
        self.session = session
        let attributes: [NSOpenGLPixelFormatAttribute] = [UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core), UInt32(NSOpenGLPFADoubleBuffer), UInt32(NSOpenGLPFAAccelerated), UInt32(NSOpenGLPFAColorSize), 24, UInt32(NSOpenGLPFAAlphaSize), 8, 0]
        super.init(frame: .zero, pixelFormat: NSOpenGLPixelFormat(attributes: attributes))
        wantsBestResolutionOpenGLSurface = true
        session.videoView = self
        setAccessibilityLabel("Video playback")
        registerForDraggedTypes([.fileURL, .URL])
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func prepareOpenGL() {
        super.prepareOpenGL()
        guard renderer == nil, let engine = session.engine, let context = openGLContext?.cglContextObj else { return }
        var interval: GLint = 1
        openGLContext?.setValues(&interval, for: .swapInterval)
        do {
            renderer = try GLRenderer(engine: engine, context: context)
            session.renderer = renderer
            reshape()
        } catch { session.errorMessage = error.localizedDescription }
    }
    override func reshape() {
        super.reshape()
        let size = convertToBacking(bounds).size
        renderer?.resize(width: Int32(size.width), height: Int32(size.height))
    }
    override func draw(_ dirtyRect: NSRect) { renderer?.draw() }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { session.perform(.fullscreen) }
        else { session.perform(.togglePause) }
    }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for command in [PlayerCommand.togglePause, .attachSubtitle, .screenshot, .toggleInspector, .toggleQueue, .fullscreen] {
            let item = NSMenuItem(title: command.title, action: #selector(AppDelegate.commandAction(_:)), keyEquivalent: "")
            item.representedObject = command.rawValue; item.target = NSApp.delegate
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        session.open(urls); return true
    }
}

struct VideoSurface: NSViewRepresentable {
    let session: PlayerSession
    func makeNSView(context: Context) -> NSView {
        if let view = VideoOpenGLView(session: session) { return view }
        session.errorMessage = "A compatible video rendering surface is unavailable on this Mac."
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
