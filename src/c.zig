const builtin = @import("builtin");

pub usingnamespace if (builtin.target.isWasm()) struct {
    // Types
    pub const GLboolean = bool;
    pub const GLfloat = f32;
    pub const GLclampf = f32;
    pub const GLuint = u32;
    pub const GLbitfield = u32;
    pub const GLint = i32;
    pub const GLintptr = i32;
    pub const GLsizei = u32;
    pub const GLsizeiptr = c_long;
    pub const GLenum = u32;

    pub const DOMString = [*c]const u8;

    pub const WebGLBuffer = GLuint;
    pub const WebGLProgram = GLuint;
    pub const WebGLShader = GLuint;
    pub const WebGLTexture = GLuint;
    pub const WebGLUniformLocation = GLint;

    pub const GL_FALSE = false;
    pub const GL_TRUE = true;

    // Constants as defined by WebGL
    pub const GL_DEPTH_BUFFER_BIT: GLenum = 0x00000100;
    pub const GL_STENCIL_BUFFER_BIT: GLenum = 0x00000400;
    pub const GL_COLOR_BUFFER_BIT: GLenum = 0x00004000;

    pub const GL_POINTS: GLenum = 0x0000;
    pub const GL_LINES: GLenum = 0x0001;
    pub const GL_LINE_LOOP: GLenum = 0x0002;
    pub const GL_LINE_STRIP: GLenum = 0x0003;
    pub const GL_TRIANGLES: GLenum = 0x0004;
    pub const GL_TRIANGLE_STRIP: GLenum = 0x0005;
    pub const GL_TRIANGLE_FAN: GLenum = 0x0006;

    pub const GL_NO_ERROR: GLenum = 0x0500;
    pub const GL_INVALID_ENUM: GLenum = 0x0500;
    pub const GL_INVALID_VALUE: GLenum = 0x0501;
    pub const GL_INVALID_OPERATION: GLenum = 0x0502;
    pub const GL_OUT_OF_MEMORY: GLenum = 0x0505;
    pub const GL_CONTEXT_LOST_WEBGL: GLenum = 0x9242;

    pub const GL_CULL_FACE: GLenum = 0x0B44;
    pub const GL_DEPTH_TEST: GLenum = 0x0B71;
    pub const GL_STENCIL_TEST: GLenum = 0x0B90;
    pub const GL_DITHER: GLenum = 0x0BD0;
    pub const GL_BLEND: GLenum = 0x0BE2;
    pub const GL_SCISSOR_TEST: GLenum = 0x0C11;
    pub const GL_POLYGON_OFFSET_FILL: GLenum = 0x8037;
    pub const GL_SAMPLE_ALPHA_TO_COVERAGE: GLenum = 0x809E;
    pub const GL_SAMPLE_COVERAGE: GLenum = 0x80A0;

    pub const GL_TEXTURE_2D: GLenum = 0x0DE1;

    pub const GL_BYTE: GLenum = 0x1400;
    pub const GL_UNSIGNED_BYTE: GLenum = 0x1401;
    pub const GL_SHORT: GLenum = 0x1402;
    pub const GL_UNSIGNED_SHORT: GLenum = 0x1403;
    pub const GL_INT: GLenum = 0x1404;
    pub const GL_UNSIGNED_INT: GLenum = 0x1405;
    pub const GL_FLOAT: GLenum = 0x1406;
    pub const GL_UNSIGNED_SHORT_4_4_4_4: GLenum = 0x8033;
    pub const GL_UNSIGNED_SHORT_5_5_5_1: GLenum = 0x8034;
    pub const GL_UNSIGNED_SHORT_5_6_5: GLenum = 0x8363;

    pub const GL_ALPHA: GLenum = 0x1906;
    pub const GL_RGB: GLenum = 0x1907;
    pub const GL_RGBA: GLenum = 0x1908;
    pub const GL_LUMINANCE: GLenum = 0x1909;
    pub const GL_LUMINANCE_ALPHA: GLenum = 0x190A;

    pub const GL_NEAREST: GLenum = 0x2600;
    pub const GL_LINEAR: GLenum = 0x2601;
    pub const GL_NEAREST_MIPMAP_NEAREST: GLenum = 0x2700;
    pub const GL_LINEAR_MIPMAP_NEAREST: GLenum = 0x2701;
    pub const GL_NEAREST_MIPMAP_LINEAR: GLenum = 0x2702;
    pub const GL_LINEAR_MIPMAP_LINEAR: GLenum = 0x2703;

    pub const GL_TEXTURE_MAG_FILTER: GLenum = 0x2800;
    pub const GL_TEXTURE_MIN_FILTER: GLenum = 0x2801;
    pub const GL_TEXTURE_WRAP_S: GLenum = 0x2802;
    pub const GL_TEXTURE_WRAP_T: GLenum = 0x2803;

    pub const GL_REPEAT: GLenum = 0x2901;
    pub const GL_CLAMP_TO_EDGE: GLenum = 0x812F;
    pub const GL_MIRRORED_REPEAT: GLenum = 0x8370;

    pub const GL_TEXTURE0: GLenum = 0x84C0; // goes up to GL_TEXTURE31
    pub const GL_TEXTURE_MAX_ANISOTROPY_EXT: GLenum = 0x84FE;
    pub const GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT: GLenum = 0x84FF;

    pub const GL_ARRAY_BUFFER: GLenum = 0x8892;
    pub const GL_ELEMENT_ARRAY_BUFFER: GLenum = 0x8893;

    pub const GL_STREAM_DRAW: GLenum = 0x88E0;
    pub const GL_STATIC_DRAW: GLenum = 0x88E4;
    pub const GL_DYNAMIC_DRAW: GLenum = 0x88E8;

    pub const GL_FRAGMENT_SHADER: GLenum = 0x8B30;
    pub const GL_VERTEX_SHADER: GLenum = 0x8B31;

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
    pub extern fn glGetUniformLocation(program: WebGLProgram, name: [*c]const u8, name_len: GLsizei) WebGLUniformLocation;
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

    //
} else @cImport({
    @cInclude("SDL.h");
    @cInclude("epoxy/gl.h");
});
