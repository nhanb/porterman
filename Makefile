PARAMS = -fsys=sdl3 -fsys=freetype

watch:
	zig build run $(PARAMS) --watch

build:
	zig build $(PARAMS)

test:
	zig build $(PARAMS) test --watch

clean:
	rm -rf zig-out .zig-cache
