const target = @import("builtin").target;

pub const GLboolean = if (target.isWasm()) bool else u8;
pub const GLfloat = f32;
pub const GLclampf = f32;
pub const GLuint = u32;
pub const GLbitfield = u32;
pub const GLint = i32;
pub const GLintptr = i32;
pub const GLsizei = i32;
pub const GLsizeiptr = c_long;
pub const GLenum = u32;
pub const GLubyte = u8;
pub const GLchar = u8; // NOTE: Actually a c_char.
