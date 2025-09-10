PARAMS = -fsys=sdl3 -fsys=freetype -fsys=sqlite3

entr:
	find . -path '*/src/*' -or -name '*.zig' -not -path '*/.zig-cache/*' | \
		entr -rc zig build run $(PARAMS)

watch:
	zig build $(PARAMS) run --watch

run:
	zig build $(PARAMS) run

build:
	zig build $(PARAMS)

test:
	zig build $(PARAMS) test --watch

clean:
	rm -rf zig-out .zig-cache
