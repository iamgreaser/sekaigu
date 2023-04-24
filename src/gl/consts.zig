const target = @import("builtin").target;

const gltypes = @import("types.zig");
const GLboolean = gltypes.GLboolean;
const GLfloat = gltypes.GLfloat;
const GLclampf = gltypes.GLclampf;
const GLuint = gltypes.GLuint;
const GLbitfield = gltypes.GLbitfield;
const GLint = gltypes.GLint;
const GLintptr = gltypes.GLintptr;
const GLsizei = gltypes.GLsizei;
const GLsizeiptr = gltypes.GLsizeiptr;
const GLenum = gltypes.GLenum;
const GLubyte = gltypes.GLubyte;

pub const GL_FALSE: GLboolean = if (target.isWasm()) false else 0;
pub const GL_TRUE: GLboolean = if (target.isWasm()) true else 1;

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
pub const GL_INVALID_FRAMEBUFFER_OPERATION: GLenum = 0x0506; // non-WebGL
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
