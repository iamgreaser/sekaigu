var canvas = document.getElementById("canvas");
var gl = canvas.getContext("webgl", {
  alpha: false,
  depth: true,
});
gl.viewport(0, 0, canvas.width, canvas.height);
var memory;
var wasm;

var M = {nexti: 1};

function into_map (obj) {
  var i = M.nexti;
  M[i] = obj;
  M.nexti += 1;
  return i;
}

function wrap_string (sptr) {
  // Set a limit of 100 KB for now.
  const maxlen = 100 * 1024;
  const buf = new Uint8Array(memory.buffer, sptr);
  for (var i = 0; i < maxlen; i++) {
    if (buf[i] == 0) {
      const result = new TextDecoder("utf-8").decode(new Uint8Array(memory.buffer, sptr, i));
      //console.log("Wrapped string: <<<" + result + ">>>");
      return result;
    }
  }
  return null; // FIXME: No NUL terminator - needs to throw an error --GM
}

function wrap_data (basetype, dptr, len) {
  //return new TextDecoder("utf-8").decode(new Uint8Array(memory.buffer, dptr, size));
  const result = new basetype(memory.buffer, dptr, len);
  //console.log("Wrapped data:", result);
  return result;
}

var importObject = {
  env: {
    console_log: (msg) => { console.log(">>> " + wrap_string(msg)); },
    glActiveTexture: (texture) => { return gl.activeTexture(texture); },
    glAttachShader: (program, shader) => { return gl.attachShader(M[program], M[shader]); },
    glBindAttribLocation: (program, index, name) => {
      const rname = wrap_string(name);
      console.log("bindattr", program, M[program], index, "[" + rname + "]");
      return gl.bindAttribLocation(M[program], index, rname);
    },
    glBindBuffer: (target, buffer) => { return gl.bindBuffer(target, M[buffer]); },
    glBindTexture: (target, texture) => { return gl.bindTexture(target, M[texture]); },
    glBufferData: (target, size, data, usage) => {
      const buf = wrap_data(Uint8Array, data, size);
      //console.log("buffer data", size, buf);
      return gl.bufferData(target, buf, usage);
    }, // wrapped on the JS side
    glClear: (mask) => { return gl.clear(mask); },
    glClearColor: (r, g, b, a) => { return gl.clearColor(r, g, b, a); },
    glCompileShader: (shader) => { return gl.compileShader(M[shader]); },
    glCreateBuffer: () => { return into_map(gl.createBuffer()); },
    glCreateProgram: () => { return into_map(gl.createProgram()); },
    glCreateShader: (type_) => { return into_map(gl.createShader(type_)); },
    glCreateTexture: () => { return into_map(gl.createTexture()); },
    glDisable: (cap) => { return gl.disable(cap); },
    glDisableVertexAttribArray: (index) => { return gl.disableVertexAttribArray(index); },
    glDrawArrays: (mode, first, count) => { return gl.drawArrays(mode, first, count); },
    glDrawElements: (mode, count, type_, offset) => { return gl.drawElements(mode, count, type_, offset); }, // wrapped on the JS side?
    glEnable: (cap) => { return gl.enable(cap); },
    glEnableVertexAttribArray: (index) => { return gl.enableVertexAttribArray(index); },
    glGenerateMipmap: (target) => { return gl.generateMipmap(target); },
    glGetError: () => { return gl.getError(); },
    glGetProgramInfoLog: (program) => { console.log("PROGRAM LOG:" + gl.getProgramInfoLog(M[program])); return wasm.exports.retstr_buf.value; },
    glGetShaderInfoLog: (shader) => { console.log("SHADER LOG:" + gl.getShaderInfoLog(M[shader])); return wasm.exports.retstr_buf.value; },
    glGetUniformLocation: (program, name) => { return into_map(gl.getUniformLocation(M[program], wrap_string(name))); },
    glIsEnabled: (cap) => { return gl.isEnabled(cap); },
    glLinkProgram: (program) => { return gl.linkProgram(M[program]); },
    glShaderSource: (shader, source) => { return gl.shaderSource(M[shader], wrap_string(source)); },
    glTexImage2D: (target, level, internalformat, width, height, border, format, type_, pixels, size) => { return gl.texImage2D(target, level, internalformat, width, height, border, format, type_, wrap_data(Uint8Array, pixels, size)); },
    glTexParameteri: (target, pname, param) => { return gl.texParameteri(target, pname, param); },
    glUseProgram: (program) => { return gl.useProgram(M[program]); },
    glUniform1i: (location_, value0) => { return gl.uniform1i(M[location_], value0); }, // wrapped on the JS side
    glUniform4fv: (location_, count, value) => { return gl.uniform4fv(M[location_], wrap_data(Float32Array, value, count*4)); }, // wrapped on the JS side
    glUniformMatrix4fv: (location_, count, transpose, value) => { return gl.uniformMatrix4fv(M[location_], transpose, wrap_data(Float32Array, value, 16*count)); }, // wrapped on the JS side
    glVertexAttribPointer: (index, size, type_, normalized, stride, offset) => {
      //console.log("AttrPtr", index, size, type_, normalized, stride, offset);
      return gl.vertexAttribPointer(index, size, type_, normalized, stride, offset);
    },
  }
};

function draw_scene(ts) {
  //console.log(ts);
  if (!wasm.exports.c_drawScene()) {
    console.log("DrawScene failed!");
  }
}

const FPS = 20.0;
var tick_interval;
function tick_scene() {
  if (!wasm.exports.c_tickScene(1.0/FPS)) {
    console.log("TickScene failed!");
  }
  window.requestAnimationFrame(draw_scene);
}

WebAssembly.instantiateStreaming(fetch("cockel.wasm"), importObject).then(
  (obj) => {
    console.log("Fetched!");
    console.log(obj.instance.exports);
    console.log(obj.instance.exports.retstr_buf_used);
    console.log(obj.instance.exports.retstr_buf);
    wasm = obj.instance;
    memory = obj.instance.exports.memory;
    if (!obj.instance.exports.c_init()) {
      console.log("Init failed!");
      obj.instance.exports.c_destroy();
      //return;
    }
    if (!obj.instance.exports.c_tickScene(0.0)) {
      console.log("TickScene failed!");
    }
    window.requestAnimationFrame(draw_scene);
    var tick_interval = window.setInterval(tick_scene, 1000.0/FPS);
  }
);
