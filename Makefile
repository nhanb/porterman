PARAMS = -fsys=sdl3 -fsys=freetype -fsys=sqlite3

entr:
	find . -path '*/src/*' -or -name '*.zig' -not -path '*/.zig-cache/*' | \
		entr -rc zig build run $(PARAMS) -- porterman.prtm

watch:
	zig build $(PARAMS) run --watch

run:
	zig build $(PARAMS) run

build:
	zig build $(PARAMS)

release:
	zig build $(PARAMS) -Doptimize=ReleaseSafe

test:
	zig build $(PARAMS) test --watch

clean:
	rm -rf zig-out .zig-cache
