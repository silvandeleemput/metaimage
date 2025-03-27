SHARED_OPTS = -show-timings
ifeq ($(OS),Windows_NT)
	EXT = .exe
	EXTRA_OPTS = -extra-linker-flags:/LTCG -subsystem:console
else
	EXT =
	EXTRA_OPTS =
endif

example:
	odin run ./example.odin -file -disable-assert -no-bounds-check -o:speed $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_example$(EXT)

example-debug:
	odin run ./example.odin -file -debug $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_example_debug$(EXT)

example2:
	odin run ./example2.odin -file -disable-assert -no-bounds-check -o:speed $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_example2$(EXT)

example2-debug:
	odin run ./example2.odin -file -debug $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_example2_debug$(EXT)

test:
	odin test ./tests $(SHARED_OPTS) $(EXTRA_OPTS) -out:./metaimage_tests$(EXT)
