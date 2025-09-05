PARAMS = -fsys=sdl3 -fsys=freetype

watch:
	zig build run $(PARAMS) --watch

build:
	zig build $(PARAMS)
