SHARED_OPTS = -show-timings
ifeq ($(OS),Windows_NT)
	EXT = .exe
	EXTRA_OPTS = -extra-linker-flags:/LTCG -subsystem:console
else
	EXT =
	EXTRA_OPTS =
endif
run:
	odin run . -disable-assert -no-bounds-check -o:speed $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_example$(EXT)

debug:
	odin run . -debug $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_example_debug$(EXT)

test:
	odin test ./tests $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_tests$(EXT)
