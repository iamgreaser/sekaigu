WARNING: CURRENTLY SORTING OUT LICENCE CONFORMANCE AND STUFF AND THIS README IS PROBABLY INCOMPLETE --GM

sekaigu (世界具): A world-building tool

Copyright © 2023 sekaigu contributors. Licensed under various licences, please see COPYING for more information.

In short, the engine is licensed under AGPLv3, the font is a modified GNU Unifont 15.0.01 (under the name "sekaigu yunifon JP 15.0.01.0") licensed under SIL OFL v1.1, other stuff that runs within the engine is CC0 - exactly what's what will be explicitly marked in each source file.

Current target version of Zig is 0.11.0-dev.3006+ff59c4584 .

It can probably be obtained from here:

* Linux, x86 64-bit: https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.3006+ff59c4584.tar.xz
  * Size: 44440580 bytes
  * minisig: https://ziglang.org/builds/zig-linux-x86_64-0.11.0-dev.3006+ff59c4584.tar.xz.minisig
  * SHA256: 145d5b66fa367277a10c25fb90a343a5fc157ab163503b349f4923e5301f5d82
* Windows, x86 64-bit: https://ziglang.org/builds/zig-windows-x86_64-0.11.0-dev.3006+ff59c4584.zip
  * Size: 77508416 bytes
  * minisig: https://ziglang.org/builds/zig-windows-x86_64-0.11.0-dev.3006+ff59c4584.zip.minisig
  * SHA256: c875a018467540cc0e75db44da2ac09b46d6997d695871e2cb20aa74a45a191a

Latest nightlies can be found here, including a few 32-bit builds: https://ziglang.org/download/

The official chat room is on IRC, `#sekaigu` on Libera Chat - point your IRC client to ircs://irc.libera.chat:6697/sekaigu

If you don't have an IRC client... TODO: suggest some good ones, HexChat is a pretty safe bet, also see what's best to use on a phone --GM

## Supported platforms

* Linux, x86 64-bit and 32-bit
* Windows, x86 64-bit and 32-bit
* WebAssembly, 32-bit

If you want this to run on your Mac, it's probably going to be your responsibility to write the platform-specific code.

## Building

Obtain the target version of Zig, and then run the following from the project root:

    zig build

The output executable will be in `zig-out/bin/`, and will either be named `sekaigu` or `sekaigu.exe`.

For convenience, a WebAssembly build (`sekaigu.wasm`) will also be in that directory, but the build which is *actually* used will be embedded into the executable.

## Running

You can either run the executable directly, or find someone who is running the executable on the network and connect to it in a web browser on port 10536.

## Currently supported targets

- Linux x86, 64-bit (other architectures not tested)
- Windows x86, 64-bit and 32-bit
- WebAssembly, 32-bit (built as part of one of the other builds)

