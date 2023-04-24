const builtin = @import("builtin");

pub usingnamespace if (builtin.target.isWasm()) struct {
    // Types
    pub const gltypes = @import("gl/types.zig");
    pub const GLboolean = gltypes.GLboolean;
    pub const GLfloat = gltypes.GLfloat;
    pub const GLclampf = gltypes.GLclampf;
    pub const GLuint = gltypes.GLuint;
    pub const GLbitfield = gltypes.GLbitfield;
    pub const GLint = gltypes.GLint;
    pub const GLintptr = gltypes.GLintptr;
    pub const GLsizei = gltypes.GLsizei;
    pub const GLsizeiptr = gltypes.GLsizeiptr;
    pub const GLenum = gltypes.GLenum;

    pub usingnamespace @import("gl/consts.zig");

    pub const DOMString = [*c]const u8;

    pub const WebGLBuffer = GLuint;
    pub const WebGLProgram = GLuint;
    pub const WebGLShader = GLuint;
    pub const WebGLTexture = GLuint;
    pub const WebGLUniformLocation = GLint;

    export var retstr_buf = [_]u8{0} ** 2048;
    export var retstr_buf_used: u32 = 0;

    // Functions
    pub extern fn console_log(line: [*c]const u8) void;
    pub extern fn fetch_event(buf: [*c]u8, size: usize) usize;

    // WebGL wrapper functions
    pub extern fn glActiveTexture(texture: GLenum) void;
    pub extern fn glAttachShader(program: WebGLProgram, shader: WebGLShader) void;
    pub extern fn glBindAttribLocation(program: WebGLProgram, index: GLuint, name: DOMString) void;
    pub extern fn glBindBuffer(target: GLenum, buffer: WebGLBuffer) void;
    pub extern fn glBindTexture(target: GLenum, texture: WebGLTexture) void;
    pub extern fn glBufferData(target: GLenum, size: GLsizeiptr, data: *allowzero const anyopaque, usage: GLenum) void; // wrapped on the JS side
    pub extern fn glClear(mask: GLbitfield) void;
    pub extern fn glClearColor(r: GLclampf, g: GLclampf, b: GLclampf, a: GLclampf) void;
    pub extern fn glCompileShader(shader: WebGLShader) void;
    pub extern fn glCreateBuffer() WebGLBuffer;
    pub extern fn glCreateProgram() WebGLProgram;
    pub extern fn glCreateShader(type_: GLenum) WebGLShader;
    pub extern fn glCreateTexture() WebGLTexture;
    pub extern fn glDisable(cap: GLenum) void;
    pub extern fn glDisableVertexAttribArray(index: GLuint) void;
    pub extern fn glDrawArrays(mode: GLenum, first: GLint, count: GLsizei) void;
    pub extern fn glDrawElements(mode: GLenum, count: GLsizei, type_: GLenum, offset: GLintptr) void; // wrapped on the JS side?
    pub extern fn glEnable(cap: GLenum) void;
    pub extern fn glEnableVertexAttribArray(index: GLuint) void;
    pub extern fn glGenerateMipmap(target: GLenum) void;
    pub extern fn glGetError() GLenum;
    pub extern fn glGetProgramInfoLog(program: WebGLProgram) DOMString;
    pub extern fn glGetShaderInfoLog(shader: WebGLShader) DOMString;
    pub extern fn glGetUniformLocation(program: WebGLProgram, name: [*c]const u8, name_len: u32) WebGLUniformLocation;
    pub extern fn glIsEnabled(cap: GLenum) GLboolean;
    pub extern fn glLinkProgram(program: WebGLProgram) void;
    pub extern fn glShaderSource(shader: WebGLShader, source: DOMString) void;
    pub extern fn glTexImage2D(target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, border: GLsizei, format: GLenum, type_: GLenum, pixels: *allowzero const anyopaque, size: GLsizei) void; // wrapped on the JS side
    pub extern fn glTexParameteri(target: GLenum, pname: GLenum, param: GLint) void;
    pub extern fn glUseProgram(program: WebGLProgram) void;
    pub extern fn glUniform1i(location: WebGLUniformLocation, value0: GLint) void; // wrapped on the JS side
    pub extern fn glUniform4fv(location: WebGLUniformLocation, count: GLsizei, value: [*c]const GLfloat) void; // wrapped on the JS side
    pub extern fn glUniformMatrix4fv(location: WebGLUniformLocation, count: GLsizei, transpose: GLboolean, value: [*c]const GLfloat) void; // wrapped on the JS side
    pub extern fn glVertexAttribPointer(index: GLuint, size: GLint, type_: GLenum, normalized: GLboolean, stride: GLsizei, offset: GLintptr) void;
    pub extern fn glViewport(x: GLint, y: GLint, width: GLsizei, height: GLsizei) void;

    //
} else struct {
    pub usingnamespace @cImport({
        @cInclude("SDL.h");
        //@cInclude("epoxy/gl.h");
    });
    pub usingnamespace @import("gl/consts.zig");
    pub usingnamespace @import("gl/apigen.zig").API;
};
