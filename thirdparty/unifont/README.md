The hex files are from the `font/precompiled/` directory in the GNU Unifont 15.0.01 distribution.
These files are licensed under the SIL Open Font License, version 1.1.
The current URL for the GNU Unifont website is here: <http://unifoundry.com/unifont/index.html>
The archive can, at the time of writing (2023-05-10T23:59+00:00), be downloaded from this page: <http://unifoundry.com/unifont/unifont-utilities.html>

The files we use to form the base of our "yunifon" fork of the GNU Unifont font are, applied in order, conflicts at glyph positions always using the earliest-provided glyphs, and the character index field extended to 6 hex digits:
- `unifont_jp-15.0.01.hex`: The Japanese variant of the plane 0 subset of Unifont.
- `unifont_upper-15.0.01.hex`: The glyphs above plane 0.

This is roughly how the formerly-used "unifont-jp-with-upper-15.0.01.hex" was generated before we got onto sorting out the licensing stuff, and so the only difference between that and what we're doing now is the filename and the font name and the fact that it's now generated using a tool.

The other files are:
- `unifont-15.0.01.hex`: The standard variant of the plane 0 subset of Unifont. Useful for when we need to support the Chinese language.

Because most of the people who will be needing to read CJK characters initially will be using it for Japanese, and the second largest group will probably be using it for Korean, it's better to use the Japanese characters for this, as the Chinese versions are actually different, and the people in charge of Unicode made the really stupid mistake of often having two actually different glyphs at given codepoints.

A classic example is the glyph 直. This is taught in second grade in Japan, and is the earliest glyph taught in the Japanese education system that will clearly determine whether your system is set up for Japanese (or Korean), or Chinese.

For a counter example, the glyph 国, which uses the traditional form 國 in Korean, they actually did the right thing and made these two separate code points.
