run:
	odin run . -disable-assert -no-bounds-check -out:./metaio_example.exe

debug:
	odin run . -debug -show-timings -out:./metaio_example_debug.exe

test:
	odin test ./tests -show-timings -out:./metaio_tests.exe
