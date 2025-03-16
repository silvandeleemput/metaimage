ifeq ($(OS),Windows_NT)
	EXT = .exe
else
	EXT =
endif
run:
	odin run . -disable-assert -no-bounds-check -show-timings -o:speed -out:./metaio_example$(EXT)

debug:
	odin run . -debug -show-timings -out:./metaio_example_debug$(EXT)

test:
	odin test ./tests -show-timings -out:./metaio_tests$(EXT)
