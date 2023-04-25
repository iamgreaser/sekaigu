const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.gl_apigen);

const WINAPI = if (builtin.os.tag == .windows) std.os.windows.WINAPI else .C;
pub const API = struct {
    const gltypes = @import("types.zig");
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
    pub const GLubyte = gltypes.GLubyte;
    pub const GLchar = gltypes.GLchar;

    //const WebGLBuffer = GLuint;
    //const WebGLProgram = GLuint;
    //const WebGLShader = GLuint;
    //const WebGLTexture = GLuint;
    //
    //const WebGLUniformLocation = GLint;
    //
    //const DOMString = [:0]const u8;

    // Generated via tools/glapigen.zig, then manually massaged to make it work properly
    // TODO: Fully automate this stage --GM
    pub extern fn glBindTexture(target: GLenum, texture: GLuint) callconv(WINAPI) void;
    pub extern fn glBlendFunc(sfactor: GLenum, dfactor: GLenum) callconv(WINAPI) void;
    pub extern fn glClear(mask: GLbitfield) callconv(WINAPI) void;
    pub extern fn glClearColor(red: GLfloat, green: GLfloat, blue: GLfloat, alpha: GLfloat) callconv(WINAPI) void;
    pub extern fn glClearStencil(s: GLint) callconv(WINAPI) void;
    pub extern fn glColorMask(red: GLboolean, green: GLboolean, blue: GLboolean, alpha: GLboolean) callconv(WINAPI) void;
    pub extern fn glCopyTexImage2D(target: GLenum, level: GLint, internalformat: GLenum, x: GLint, y: GLint, width: GLsizei, height: GLsizei, border: GLint) callconv(WINAPI) void;
    pub extern fn glCopyTexSubImage2D(target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, x: GLint, y: GLint, width: GLsizei, height: GLsizei) callconv(WINAPI) void;
    pub extern fn glCullFace(mode: GLenum) callconv(WINAPI) void;
    pub extern fn glDeleteTextures(n: GLsizei, textures: *const GLuint) callconv(WINAPI) void;
    pub extern fn glDepthFunc(func: GLenum) callconv(WINAPI) void;
    pub extern fn glDepthMask(flag: GLboolean) callconv(WINAPI) void;
    pub extern fn glDisable(cap: GLenum) callconv(WINAPI) void;
    pub extern fn glDrawArrays(mode: GLenum, first: GLint, count: GLsizei) callconv(WINAPI) void;
    pub extern fn glDrawElements(mode: GLenum, count: GLsizei, type_: GLenum, indices: ?*const anyopaque) callconv(WINAPI) void;
    pub extern fn glEnable(cap: GLenum) callconv(WINAPI) void;
    pub extern fn glFinish() callconv(WINAPI) void;
    pub extern fn glFlush() callconv(WINAPI) void;
    pub extern fn glFrontFace(mode: GLenum) callconv(WINAPI) void;
    pub extern fn glGenTextures(n: GLsizei, textures: [*]GLuint) callconv(WINAPI) void;
    pub extern fn glGetBooleanv(pname: GLenum, data: *GLboolean) callconv(WINAPI) void;
    pub extern fn glGetError() callconv(WINAPI) GLenum;
    pub extern fn glGetFloatv(pname: GLenum, data: *GLfloat) callconv(WINAPI) void;
    pub extern fn glGetIntegerv(pname: GLenum, data: *GLint) callconv(WINAPI) void;
    pub extern fn glGetString(name: GLenum) callconv(WINAPI) *const GLubyte;
    pub extern fn glGetTexParameterfv(target: GLenum, pname: GLenum, params: *GLfloat) callconv(WINAPI) void;
    pub extern fn glGetTexParameteriv(target: GLenum, pname: GLenum, params: *GLint) callconv(WINAPI) void;
    pub extern fn glHint(target: GLenum, mode: GLenum) callconv(WINAPI) void;
    pub extern fn glIsEnabled(cap: GLenum) callconv(WINAPI) GLboolean;
    pub extern fn glIsTexture(texture: GLuint) callconv(WINAPI) GLboolean;
    pub extern fn glLineWidth(width: GLfloat) callconv(WINAPI) void;
    pub extern fn glPixelStorei(pname: GLenum, param: GLint) callconv(WINAPI) void;
    pub extern fn glPolygonOffset(factor: GLfloat, units: GLfloat) callconv(WINAPI) void;
    pub extern fn glReadPixels(x: GLint, y: GLint, width: GLsizei, height: GLsizei, format: GLenum, type_: GLenum, pixels: **void) callconv(WINAPI) void;
    pub extern fn glScissor(x: GLint, y: GLint, width: GLsizei, height: GLsizei) callconv(WINAPI) void;
    pub extern fn glStencilFunc(func: GLenum, ref: GLint, mask: GLuint) callconv(WINAPI) void;
    pub extern fn glStencilMask(mask: GLuint) callconv(WINAPI) void;
    pub extern fn glStencilOp(fail: GLenum, zfail: GLenum, zpass: GLenum) callconv(WINAPI) void;
    pub extern fn glTexImage2D(target: GLenum, level: GLint, internalformat: GLint, width: GLsizei, height: GLsizei, border: GLint, format: GLenum, type_: GLenum, pixels: *const anyopaque) callconv(WINAPI) void;
    pub extern fn glTexParameterf(target: GLenum, pname: GLenum, param: GLfloat) callconv(WINAPI) void;
    pub extern fn glTexParameterfv(target: GLenum, pname: GLenum, params: *const GLfloat) callconv(WINAPI) void;
    pub extern fn glTexParameteri(target: GLenum, pname: GLenum, param: GLint) callconv(WINAPI) void;
    pub extern fn glTexParameteriv(target: GLenum, pname: GLenum, params: *const GLint) callconv(WINAPI) void;
    pub extern fn glTexSubImage2D(target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, type_: GLenum, pixels: *const void) callconv(WINAPI) void;
    pub extern fn glViewport(x: GLint, y: GLint, width: GLsizei, height: GLsizei) callconv(WINAPI) void;

    pub var extensions: struct {
        glActiveTexture: *const fn (texture: GLenum) callconv(WINAPI) void = undefined,
        glAttachShader: *const fn (program: GLuint, shader: GLuint) callconv(WINAPI) void = undefined,
        glBindAttribLocation: *const fn (program: GLuint, index: GLuint, name: [*:0]const GLchar) callconv(WINAPI) void = undefined,
        glBindBuffer: *const fn (target: GLenum, buffer: GLuint) callconv(WINAPI) void = undefined,
        glBindFramebuffer: *const fn (target: GLenum, framebuffer: GLuint) callconv(WINAPI) void = undefined,
        glBindRenderbuffer: *const fn (target: GLenum, renderbuffer: GLuint) callconv(WINAPI) void = undefined,
        glBlendColor: *const fn (red: GLfloat, green: GLfloat, blue: GLfloat, alpha: GLfloat) callconv(WINAPI) void = undefined,
        glBlendEquation: *const fn (mode: GLenum) callconv(WINAPI) void = undefined,
        glBlendEquationSeparate: *const fn (modeRGB: GLenum, modeAlpha: GLenum) callconv(WINAPI) void = undefined,
        glBlendFuncSeparate: *const fn (sfactorRGB: GLenum, dfactorRGB: GLenum, sfactorAlpha: GLenum, dfactorAlpha: GLenum) callconv(WINAPI) void = undefined,
        glBufferData: *const fn (target: GLenum, size: GLsizeiptr, data: ?*const anyopaque, usage: GLenum) callconv(WINAPI) void = undefined,
        glBufferSubData: *const fn (target: GLenum, offset: GLintptr, size: GLsizeiptr, data: *const void) callconv(WINAPI) void = undefined,
        glCheckFramebufferStatus: *const fn (target: GLenum) callconv(WINAPI) GLenum = undefined,
        glClearDepthf: *const fn (d: GLfloat) callconv(WINAPI) void = undefined,
        glCompileShader: *const fn (shader: GLuint) callconv(WINAPI) void = undefined,
        glCompressedTexImage2D: *const fn (target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, height: GLsizei, border: GLint, imageSize: GLsizei, data: *const void) callconv(WINAPI) void = undefined,
        glCompressedTexSubImage2D: *const fn (target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, imageSize: GLsizei, data: *const void) callconv(WINAPI) void = undefined,
        glCreateProgram: *const fn () callconv(WINAPI) GLuint = undefined,
        glCreateShader: *const fn (type_: GLenum) callconv(WINAPI) GLuint = undefined,
        glDeleteBuffers: *const fn (n: GLsizei, buffers: *const GLuint) callconv(WINAPI) void = undefined,
        glDeleteFramebuffers: *const fn (n: GLsizei, framebuffers: *const GLuint) callconv(WINAPI) void = undefined,
        glDeleteProgram: *const fn (program: GLuint) callconv(WINAPI) void = undefined,
        glDeleteRenderbuffers: *const fn (n: GLsizei, renderbuffers: *const GLuint) callconv(WINAPI) void = undefined,
        glDeleteShader: *const fn (shader: GLuint) callconv(WINAPI) void = undefined,
        glDepthRangef: *const fn (n: GLfloat, f: GLfloat) callconv(WINAPI) void = undefined,
        glDetachShader: *const fn (program: GLuint, shader: GLuint) callconv(WINAPI) void = undefined,
        glDisableVertexAttribArray: *const fn (index: GLuint) callconv(WINAPI) void = undefined,
        glEnableVertexAttribArray: *const fn (index: GLuint) callconv(WINAPI) void = undefined,
        glFramebufferRenderbuffer: *const fn (target: GLenum, attachment: GLenum, renderbuffertarget: GLenum, renderbuffer: GLuint) callconv(WINAPI) void = undefined,
        glFramebufferTexture2D: *const fn (target: GLenum, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint) callconv(WINAPI) void = undefined,
        glGenBuffers: *const fn (n: GLsizei, buffers: *GLuint) callconv(WINAPI) void = undefined,
        glGenFramebuffers: *const fn (n: GLsizei, framebuffers: *GLuint) callconv(WINAPI) void = undefined,
        glGenRenderbuffers: *const fn (n: GLsizei, renderbuffers: *GLuint) callconv(WINAPI) void = undefined,
        glGenerateMipmap: *const fn (target: GLenum) callconv(WINAPI) void = undefined,
        glGetActiveAttrib: *const fn (program: GLuint, index: GLuint, bufSize: GLsizei, length: *GLsizei, size: *GLint, type_: *GLenum, name: [*:0]GLchar) callconv(WINAPI) void = undefined,
        glGetActiveUniform: *const fn (program: GLuint, index: GLuint, bufSize: GLsizei, length: *GLsizei, size: *GLint, type_: *GLenum, name: [*:0]GLchar) callconv(WINAPI) void = undefined,
        glGetAttachedShaders: *const fn (program: GLuint, maxCount: GLsizei, count: *GLsizei, shaders: *GLuint) callconv(WINAPI) void = undefined,
        glGetAttribLocation: *const fn (program: GLuint, name: [*:0]const GLchar) callconv(WINAPI) GLint = undefined,
        glGetBufferParameteriv: *const fn (target: GLenum, pname: GLenum, params: *GLint) callconv(WINAPI) void = undefined,
        glGetFramebufferAttachmentParameteriv: *const fn (target: GLenum, attachment: GLenum, pname: GLenum, params: *GLint) callconv(WINAPI) void = undefined,
        glGetProgramInfoLog: *const fn (program: GLuint, bufSize: GLsizei, length: *GLsizei, infoLog: [*:0]GLchar) callconv(WINAPI) void = undefined,
        glGetProgramiv: *const fn (program: GLuint, pname: GLenum, params: *GLint) callconv(WINAPI) void = undefined,
        glGetRenderbufferParameteriv: *const fn (target: GLenum, pname: GLenum, params: *GLint) callconv(WINAPI) void = undefined,
        glGetShaderInfoLog: *const fn (shader: GLuint, bufSize: GLsizei, length: *GLsizei, infoLog: [*:0]GLchar) callconv(WINAPI) void = undefined,
        glGetShaderPrecisionFormat: *const fn (shadertype_: GLenum, precisiontype: GLenum, range: *GLint, precision: *GLint) callconv(WINAPI) void = undefined,
        glGetShaderSource: *const fn (shader: GLuint, bufSize: GLsizei, length: *GLsizei, source: [*:0]GLchar) callconv(WINAPI) void = undefined,
        glGetShaderiv: *const fn (shader: GLuint, pname: GLenum, params: *GLint) callconv(WINAPI) void = undefined,
        glGetUniformLocation: *const fn (program: GLuint, name: [*:0]const GLchar) callconv(WINAPI) GLint = undefined,
        glGetUniformfv: *const fn (program: GLuint, location: GLint, params: *GLfloat) callconv(WINAPI) void = undefined,
        glGetUniformiv: *const fn (program: GLuint, location: GLint, params: *GLint) callconv(WINAPI) void = undefined,
        glGetVertexAttribPointerv: *const fn (index: GLuint, pname: GLenum, pointer: **void) callconv(WINAPI) void = undefined,
        glGetVertexAttribfv: *const fn (index: GLuint, pname: GLenum, params: *GLfloat) callconv(WINAPI) void = undefined,
        glGetVertexAttribiv: *const fn (index: GLuint, pname: GLenum, params: *GLint) callconv(WINAPI) void = undefined,
        glIsBuffer: *const fn (buffer: GLuint) callconv(WINAPI) GLboolean = undefined,
        glIsFramebuffer: *const fn (framebuffer: GLuint) callconv(WINAPI) GLboolean = undefined,
        glIsProgram: *const fn (program: GLuint) callconv(WINAPI) GLboolean = undefined,
        glIsRenderbuffer: *const fn (renderbuffer: GLuint) callconv(WINAPI) GLboolean = undefined,
        glIsShader: *const fn (shader: GLuint) callconv(WINAPI) GLboolean = undefined,
        glLinkProgram: *const fn (program: GLuint) callconv(WINAPI) void = undefined,
        glReleaseShaderCompiler: *const fn () callconv(WINAPI) void = undefined,
        glRenderbufferStorage: *const fn (target: GLenum, internalformat: GLenum, width: GLsizei, height: GLsizei) callconv(WINAPI) void = undefined,
        glSampleCoverage: *const fn (value: GLfloat, invert: GLboolean) callconv(WINAPI) void = undefined,
        glShaderBinary: *const fn (count: GLsizei, shaders: *const GLuint, binaryFormat: GLenum, binary: *const void, length: GLsizei) callconv(WINAPI) void = undefined,
        glShaderSource: *const fn (shader: GLuint, count: GLsizei, string: [*]const [*:0]const GLchar, length: ?*const GLint) callconv(WINAPI) void = undefined,
        glStencilFuncSeparate: *const fn (face: GLenum, func: GLenum, ref: GLint, mask: GLuint) callconv(WINAPI) void = undefined,
        glStencilMaskSeparate: *const fn (face: GLenum, mask: GLuint) callconv(WINAPI) void = undefined,
        glStencilOpSeparate: *const fn (face: GLenum, sfail: GLenum, dpfail: GLenum, dppass: GLenum) callconv(WINAPI) void = undefined,
        glUniform1f: *const fn (location: GLint, v0: GLfloat) callconv(WINAPI) void = undefined,
        glUniform1fv: *const fn (location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void = undefined,
        glUniform1i: *const fn (location: GLint, v0: GLint) callconv(WINAPI) void = undefined,
        glUniform1iv: *const fn (location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void = undefined,
        glUniform2f: *const fn (location: GLint, v0: GLfloat, v1: GLfloat) callconv(WINAPI) void = undefined,
        glUniform2fv: *const fn (location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void = undefined,
        glUniform2i: *const fn (location: GLint, v0: GLint, v1: GLint) callconv(WINAPI) void = undefined,
        glUniform2iv: *const fn (location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void = undefined,
        glUniform3f: *const fn (location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat) callconv(WINAPI) void = undefined,
        glUniform3fv: *const fn (location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void = undefined,
        glUniform3i: *const fn (location: GLint, v0: GLint, v1: GLint, v2: GLint) callconv(WINAPI) void = undefined,
        glUniform3iv: *const fn (location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void = undefined,
        glUniform4f: *const fn (location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat, v3: GLfloat) callconv(WINAPI) void = undefined,
        glUniform4fv: *const fn (location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void = undefined,
        glUniform4i: *const fn (location: GLint, v0: GLint, v1: GLint, v2: GLint, v3: GLint) callconv(WINAPI) void = undefined,
        glUniform4iv: *const fn (location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void = undefined,
        glUniformMatrix2fv: *const fn (location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(WINAPI) void = undefined,
        glUniformMatrix3fv: *const fn (location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(WINAPI) void = undefined,
        glUniformMatrix4fv: *const fn (location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(WINAPI) void = undefined,
        glUseProgram: *const fn (program: GLuint) callconv(WINAPI) void = undefined,
        glValidateProgram: *const fn (program: GLuint) callconv(WINAPI) void = undefined,
        glVertexAttrib1f: *const fn (index: GLuint, x: GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttrib1fv: *const fn (index: GLuint, v: *const GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttrib2f: *const fn (index: GLuint, x: GLfloat, y: GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttrib2fv: *const fn (index: GLuint, v: *const GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttrib3f: *const fn (index: GLuint, x: GLfloat, y: GLfloat, z: GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttrib3fv: *const fn (index: GLuint, v: *const GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttrib4f: *const fn (index: GLuint, x: GLfloat, y: GLfloat, z: GLfloat, w: GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttrib4fv: *const fn (index: GLuint, v: *const GLfloat) callconv(WINAPI) void = undefined,
        glVertexAttribPointer: *const fn (index: GLuint, size: GLint, type_: GLenum, normalized: GLboolean, stride: GLsizei, pointer: ?*const anyopaque) callconv(WINAPI) void = undefined,
    } = .{};

    pub fn glActiveTexture(texture: GLenum) callconv(WINAPI) void {
        return extensions.glActiveTexture(texture);
    }

    pub fn glAttachShader(program: GLuint, shader: GLuint) callconv(WINAPI) void {
        return extensions.glAttachShader(program, shader);
    }

    pub fn glBindAttribLocation(program: GLuint, index: GLuint, name: [*:0]const GLchar) callconv(WINAPI) void {
        return extensions.glBindAttribLocation(program, index, name);
    }

    pub fn glBindBuffer(target: GLenum, buffer: GLuint) callconv(WINAPI) void {
        return extensions.glBindBuffer(target, buffer);
    }

    pub fn glBindFramebuffer(target: GLenum, framebuffer: GLuint) callconv(WINAPI) void {
        return extensions.glBindFramebuffer(target, framebuffer);
    }

    pub fn glBindRenderbuffer(target: GLenum, renderbuffer: GLuint) callconv(WINAPI) void {
        return extensions.glBindRenderbuffer(target, renderbuffer);
    }

    pub fn glBlendColor(red: GLfloat, green: GLfloat, blue: GLfloat, alpha: GLfloat) callconv(WINAPI) void {
        return extensions.glBlendColor(red, green, blue, alpha);
    }

    pub fn glBlendEquation(mode: GLenum) callconv(WINAPI) void {
        return extensions.glBlendEquation(mode);
    }

    pub fn glBlendEquationSeparate(modeRGB: GLenum, modeAlpha: GLenum) callconv(WINAPI) void {
        return extensions.glBlendEquationSeparate(modeRGB, modeAlpha);
    }

    pub fn glBlendFuncSeparate(sfactorRGB: GLenum, dfactorRGB: GLenum, sfactorAlpha: GLenum, dfactorAlpha: GLenum) callconv(WINAPI) void {
        return extensions.glBlendFuncSeparate(sfactorRGB, dfactorRGB, sfactorAlpha, dfactorAlpha);
    }

    pub fn glBufferData(target: GLenum, size: GLsizeiptr, data: ?*const anyopaque, usage: GLenum) callconv(WINAPI) void {
        return extensions.glBufferData(target, size, data, usage);
    }

    pub fn glBufferSubData(target: GLenum, offset: GLintptr, size: GLsizeiptr, data: *const void) callconv(WINAPI) void {
        return extensions.glBufferSubData(target, offset, size, data);
    }

    pub fn glCheckFramebufferStatus(target: GLenum) callconv(WINAPI) GLenum {
        return extensions.glCheckFramebufferStatus(target);
    }

    pub fn glClearDepthf(d: GLfloat) callconv(WINAPI) void {
        return extensions.glClearDepthf(d);
    }

    pub fn glCompileShader(shader: GLuint) callconv(WINAPI) void {
        return extensions.glCompileShader(shader);
    }

    pub fn glCompressedTexImage2D(target: GLenum, level: GLint, internalformat: GLenum, width: GLsizei, height: GLsizei, border: GLint, imageSize: GLsizei, data: *const void) callconv(WINAPI) void {
        return extensions.glCompressedTexImage2D(target, level, internalformat, width, height, border, imageSize, data);
    }

    pub fn glCompressedTexSubImage2D(target: GLenum, level: GLint, xoffset: GLint, yoffset: GLint, width: GLsizei, height: GLsizei, format: GLenum, imageSize: GLsizei, data: *const void) callconv(WINAPI) void {
        return extensions.glCompressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, imageSize, data);
    }

    pub fn glCreateProgram() callconv(WINAPI) GLuint {
        return extensions.glCreateProgram();
    }

    pub fn glCreateShader(type_: GLenum) callconv(WINAPI) GLuint {
        return extensions.glCreateShader(type_);
    }

    pub fn glDeleteBuffers(n: GLsizei, buffers: *const GLuint) callconv(WINAPI) void {
        return extensions.glDeleteBuffers(n, buffers);
    }

    pub fn glDeleteFramebuffers(n: GLsizei, framebuffers: *const GLuint) callconv(WINAPI) void {
        return extensions.glDeleteFramebuffers(n, framebuffers);
    }

    pub fn glDeleteProgram(program: GLuint) callconv(WINAPI) void {
        return extensions.glDeleteProgram(program);
    }

    pub fn glDeleteRenderbuffers(n: GLsizei, renderbuffers: *const GLuint) callconv(WINAPI) void {
        return extensions.glDeleteRenderbuffers(n, renderbuffers);
    }

    pub fn glDeleteShader(shader: GLuint) callconv(WINAPI) void {
        return extensions.glDeleteShader(shader);
    }

    pub fn glDepthRangef(n: GLfloat, f: GLfloat) callconv(WINAPI) void {
        return extensions.glDepthRangef(n, f);
    }

    pub fn glDetachShader(program: GLuint, shader: GLuint) callconv(WINAPI) void {
        return extensions.glDetachShader(program, shader);
    }

    pub fn glDisableVertexAttribArray(index: GLuint) callconv(WINAPI) void {
        return extensions.glDisableVertexAttribArray(index);
    }

    pub fn glEnableVertexAttribArray(index: GLuint) callconv(WINAPI) void {
        return extensions.glEnableVertexAttribArray(index);
    }

    pub fn glFramebufferRenderbuffer(target: GLenum, attachment: GLenum, renderbuffertarget: GLenum, renderbuffer: GLuint) callconv(WINAPI) void {
        return extensions.glFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer);
    }

    pub fn glFramebufferTexture2D(target: GLenum, attachment: GLenum, textarget: GLenum, texture: GLuint, level: GLint) callconv(WINAPI) void {
        return extensions.glFramebufferTexture2D(target, attachment, textarget, texture, level);
    }

    pub fn glGenBuffers(n: GLsizei, buffers: *GLuint) callconv(WINAPI) void {
        return extensions.glGenBuffers(n, buffers);
    }

    pub fn glGenFramebuffers(n: GLsizei, framebuffers: *GLuint) callconv(WINAPI) void {
        return extensions.glGenFramebuffers(n, framebuffers);
    }

    pub fn glGenRenderbuffers(n: GLsizei, renderbuffers: *GLuint) callconv(WINAPI) void {
        return extensions.glGenRenderbuffers(n, renderbuffers);
    }

    pub fn glGenerateMipmap(target: GLenum) callconv(WINAPI) void {
        return extensions.glGenerateMipmap(target);
    }

    pub fn glGetActiveAttrib(program: GLuint, index: GLuint, bufSize: GLsizei, length: *GLsizei, size: *GLint, type_: *GLenum, name: [*:0]GLchar) callconv(WINAPI) void {
        return extensions.glGetActiveAttrib(program, index, bufSize, length, size, type_, name);
    }

    pub fn glGetActiveUniform(program: GLuint, index: GLuint, bufSize: GLsizei, length: *GLsizei, size: *GLint, type_: *GLenum, name: [*:0]GLchar) callconv(WINAPI) void {
        return extensions.glGetActiveUniform(program, index, bufSize, length, size, type_, name);
    }

    pub fn glGetAttachedShaders(program: GLuint, maxCount: GLsizei, count: *GLsizei, shaders: *GLuint) callconv(WINAPI) void {
        return extensions.glGetAttachedShaders(program, maxCount, count, shaders);
    }

    pub fn glGetAttribLocation(program: GLuint, name: [*:0]const GLchar) callconv(WINAPI) GLint {
        return extensions.glGetAttribLocation(program, name);
    }

    pub fn glGetBufferParameteriv(target: GLenum, pname: GLenum, params: *GLint) callconv(WINAPI) void {
        return extensions.glGetBufferParameteriv(target, pname, params);
    }

    pub fn glGetFramebufferAttachmentParameteriv(target: GLenum, attachment: GLenum, pname: GLenum, params: *GLint) callconv(WINAPI) void {
        return extensions.glGetFramebufferAttachmentParameteriv(target, attachment, pname, params);
    }

    pub fn glGetProgramInfoLog(program: GLuint, bufSize: GLsizei, length: *GLsizei, infoLog: [*:0]GLchar) callconv(WINAPI) void {
        return extensions.glGetProgramInfoLog(program, bufSize, length, infoLog);
    }

    pub fn glGetProgramiv(program: GLuint, pname: GLenum, params: *GLint) callconv(WINAPI) void {
        return extensions.glGetProgramiv(program, pname, params);
    }

    pub fn glGetRenderbufferParameteriv(target: GLenum, pname: GLenum, params: *GLint) callconv(WINAPI) void {
        return extensions.glGetRenderbufferParameteriv(target, pname, params);
    }

    pub fn glGetShaderInfoLog(shader: GLuint, bufSize: GLsizei, length: *GLsizei, infoLog: [*:0]GLchar) callconv(WINAPI) void {
        return extensions.glGetShaderInfoLog(shader, bufSize, length, infoLog);
    }

    pub fn glGetShaderPrecisionFormat(shadertype: GLenum, precisiontype: GLenum, range: *GLint, precision: *GLint) callconv(WINAPI) void {
        return extensions.glGetShaderPrecisionFormat(shadertype, precisiontype, range, precision);
    }

    pub fn glGetShaderSource(shader: GLuint, bufSize: GLsizei, length: *GLsizei, source: [*:0]GLchar) callconv(WINAPI) void {
        return extensions.glGetShaderSource(shader, bufSize, length, source);
    }

    pub fn glGetShaderiv(shader: GLuint, pname: GLenum, params: *GLint) callconv(WINAPI) void {
        return extensions.glGetShaderiv(shader, pname, params);
    }

    pub fn glGetUniformLocation(program: GLuint, name: [*:0]const GLchar) callconv(WINAPI) GLint {
        return extensions.glGetUniformLocation(program, name);
    }

    pub fn glGetUniformfv(program: GLuint, location: GLint, params: *GLfloat) callconv(WINAPI) void {
        return extensions.glGetUniformfv(program, location, params);
    }

    pub fn glGetUniformiv(program: GLuint, location: GLint, params: *GLint) callconv(WINAPI) void {
        return extensions.glGetUniformiv(program, location, params);
    }

    pub fn glGetVertexAttribPointerv(index: GLuint, pname: GLenum, pointer: **void) callconv(WINAPI) void {
        return extensions.glGetVertexAttribPointerv(index, pname, pointer);
    }

    pub fn glGetVertexAttribfv(index: GLuint, pname: GLenum, params: *GLfloat) callconv(WINAPI) void {
        return extensions.glGetVertexAttribfv(index, pname, params);
    }

    pub fn glGetVertexAttribiv(index: GLuint, pname: GLenum, params: *GLint) callconv(WINAPI) void {
        return extensions.glGetVertexAttribiv(index, pname, params);
    }

    pub fn glIsBuffer(buffer: GLuint) callconv(WINAPI) GLboolean {
        return extensions.glIsBuffer(buffer);
    }

    pub fn glIsFramebuffer(framebuffer: GLuint) callconv(WINAPI) GLboolean {
        return extensions.glIsFramebuffer(framebuffer);
    }

    pub fn glIsProgram(program: GLuint) callconv(WINAPI) GLboolean {
        return extensions.glIsProgram(program);
    }

    pub fn glIsRenderbuffer(renderbuffer: GLuint) callconv(WINAPI) GLboolean {
        return extensions.glIsRenderbuffer(renderbuffer);
    }

    pub fn glIsShader(shader: GLuint) callconv(WINAPI) GLboolean {
        return extensions.glIsShader(shader);
    }

    pub fn glLinkProgram(program: GLuint) callconv(WINAPI) void {
        return extensions.glLinkProgram(program);
    }

    pub fn glReleaseShaderCompiler() callconv(WINAPI) void {
        return extensions.glReleaseShaderCompiler();
    }

    pub fn glRenderbufferStorage(target: GLenum, internalformat: GLenum, width: GLsizei, height: GLsizei) callconv(WINAPI) void {
        return extensions.glRenderbufferStorage(target, internalformat, width, height);
    }

    pub fn glSampleCoverage(value: GLfloat, invert: GLboolean) callconv(WINAPI) void {
        return extensions.glSampleCoverage(value, invert);
    }

    pub fn glShaderBinary(count: GLsizei, shaders: *const GLuint, binaryFormat: GLenum, binary: *const void, length: GLsizei) callconv(WINAPI) void {
        return extensions.glShaderBinary(count, shaders, binaryFormat, binary, length);
    }

    pub fn glShaderSource(shader: GLuint, count: GLsizei, string: [*]const [*:0]const GLchar, length: ?*const GLint) callconv(WINAPI) void {
        return extensions.glShaderSource(shader, count, string, length);
    }

    pub fn glStencilFuncSeparate(face: GLenum, func: GLenum, ref: GLint, mask: GLuint) callconv(WINAPI) void {
        return extensions.glStencilFuncSeparate(face, func, ref, mask);
    }

    pub fn glStencilMaskSeparate(face: GLenum, mask: GLuint) callconv(WINAPI) void {
        return extensions.glStencilMaskSeparate(face, mask);
    }

    pub fn glStencilOpSeparate(face: GLenum, sfail: GLenum, dpfail: GLenum, dppass: GLenum) callconv(WINAPI) void {
        return extensions.glStencilOpSeparate(face, sfail, dpfail, dppass);
    }

    pub fn glUniform1f(location: GLint, v0: GLfloat) callconv(WINAPI) void {
        return extensions.glUniform1f(location, v0);
    }

    pub fn glUniform1fv(location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void {
        return extensions.glUniform1fv(location, count, value);
    }

    pub fn glUniform1i(location: GLint, v0: GLint) callconv(WINAPI) void {
        return extensions.glUniform1i(location, v0);
    }

    pub fn glUniform1iv(location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void {
        return extensions.glUniform1iv(location, count, value);
    }

    pub fn glUniform2f(location: GLint, v0: GLfloat, v1: GLfloat) callconv(WINAPI) void {
        return extensions.glUniform2f(location, v0, v1);
    }

    pub fn glUniform2fv(location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void {
        return extensions.glUniform2fv(location, count, value);
    }

    pub fn glUniform2i(location: GLint, v0: GLint, v1: GLint) callconv(WINAPI) void {
        return extensions.glUniform2i(location, v0, v1);
    }

    pub fn glUniform2iv(location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void {
        return extensions.glUniform2iv(location, count, value);
    }

    pub fn glUniform3f(location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat) callconv(WINAPI) void {
        return extensions.glUniform3f(location, v0, v1, v2);
    }

    pub fn glUniform3fv(location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void {
        return extensions.glUniform3fv(location, count, value);
    }

    pub fn glUniform3i(location: GLint, v0: GLint, v1: GLint, v2: GLint) callconv(WINAPI) void {
        return extensions.glUniform3i(location, v0, v1, v2);
    }

    pub fn glUniform3iv(location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void {
        return extensions.glUniform3iv(location, count, value);
    }

    pub fn glUniform4f(location: GLint, v0: GLfloat, v1: GLfloat, v2: GLfloat, v3: GLfloat) callconv(WINAPI) void {
        return extensions.glUniform4f(location, v0, v1, v2, v3);
    }

    pub fn glUniform4fv(location: GLint, count: GLsizei, value: [*]const GLfloat) callconv(WINAPI) void {
        return extensions.glUniform4fv(location, count, value);
    }

    pub fn glUniform4i(location: GLint, v0: GLint, v1: GLint, v2: GLint, v3: GLint) callconv(WINAPI) void {
        return extensions.glUniform4i(location, v0, v1, v2, v3);
    }

    pub fn glUniform4iv(location: GLint, count: GLsizei, value: [*]const GLint) callconv(WINAPI) void {
        return extensions.glUniform4iv(location, count, value);
    }

    pub fn glUniformMatrix2fv(location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(WINAPI) void {
        return extensions.glUniformMatrix2fv(location, count, transpose, value);
    }

    pub fn glUniformMatrix3fv(location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(WINAPI) void {
        return extensions.glUniformMatrix3fv(location, count, transpose, value);
    }

    pub fn glUniformMatrix4fv(location: GLint, count: GLsizei, transpose: GLboolean, value: [*]const GLfloat) callconv(WINAPI) void {
        return extensions.glUniformMatrix4fv(location, count, transpose, value);
    }

    pub fn glUseProgram(program: GLuint) callconv(WINAPI) void {
        return extensions.glUseProgram(program);
    }

    pub fn glValidateProgram(program: GLuint) callconv(WINAPI) void {
        return extensions.glValidateProgram(program);
    }

    pub fn glVertexAttrib1f(index: GLuint, x: GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib1f(index, x);
    }

    pub fn glVertexAttrib1fv(index: GLuint, v: *const GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib1fv(index, v);
    }

    pub fn glVertexAttrib2f(index: GLuint, x: GLfloat, y: GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib2f(index, x, y);
    }

    pub fn glVertexAttrib2fv(index: GLuint, v: *const GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib2fv(index, v);
    }

    pub fn glVertexAttrib3f(index: GLuint, x: GLfloat, y: GLfloat, z: GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib3f(index, x, y, z);
    }

    pub fn glVertexAttrib3fv(index: GLuint, v: *const GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib3fv(index, v);
    }

    pub fn glVertexAttrib4f(index: GLuint, x: GLfloat, y: GLfloat, z: GLfloat, w: GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib4f(index, x, y, z, w);
    }

    pub fn glVertexAttrib4fv(index: GLuint, v: *const GLfloat) callconv(WINAPI) void {
        return extensions.glVertexAttrib4fv(index, v);
    }

    pub fn glVertexAttribPointer(index: GLuint, size: GLint, type_: GLenum, normalized: GLboolean, stride: GLsizei, pointer: ?*const anyopaque) callconv(WINAPI) void {
        return extensions.glVertexAttribPointer(index, size, type_, normalized, stride, pointer);
    }

    // END OF AUTOGENERATED CODE

    // Extension loader
    pub fn loadGlExtensions(comptime GPAType: type, comptime GPA: GPAType) !void {
        try loadGlExtensionsForStruct(&extensions, GPAType, GPA);
    }
    fn loadGlExtensionsForStruct(comptime api: anytype, comptime GPAType: type, comptime GPA: GPAType) !void {
        inline for (@typeInfo(@TypeOf(api.*)).Struct.fields) |field| {
            const name: [field.name.len + 1:0]u8 = (field.name ++ "\x00").*;
            log.debug("Loading proc address \"{s}\"", .{name});
            const ptr = GPA(&name);
            if (@ptrToInt(ptr) == 0) {
                log.err("Failed to load proc address for \"{s}\"", .{name});
                return error.NotFound;
            } else {
                @field(api.*, field.name) = @ptrCast(field.type, ptr);
            }
        }
    }
};
