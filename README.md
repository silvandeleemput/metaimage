# MetaImage Odin library

* Version: v1.0.0,
* Build and tested with: ODIN dev-2025-03

A simple and lightweight Odin lang library for reading and writing the ITK MetaImage file format. The library implements a small subset of the ITK MetaIO features with a strong focus on MetaImage objects.

ITK MetaImage documentation:
https://itk.org/Wiki/ITK/MetaIO/Documentation#MetaImage

Odin Programming Language: \
https://odin-lang.org/


## Features
* A single file package which implements reading and writing (.mha) and (.mhd/.raw/.zraw) MetaImages
* Support for zlib compression/decompression using vendor:zlib with customization options using metaio.ZLIBCompressionOptions struct
* Support for file and stream IO
* Support for metadata in a string:string dictionary (img.MetaData)
* Tests for core functionality under Windows and Linux

## Disclaimer

This is my first Odin project which I created in my spare time to learn Odin and low-level programming and is inteded to be used in other projects. Suggestions or improvements are welcome. Although the main functionality of the library is covered by tests, use at your own risk!

### Limitations
* No support for MetaImage files with multiple external data files, i.e. ElementDataFile can either be LOCAL or a filename pointing to a single data file (.raw/.zraw)
* ObjectType only supports Image
* Some MetaObject tags and their associated values are not explicitly supported. However, when present in the header they will be available in the MetaData dict (img.MetaData) as string:string pairs


## Prerequisites

Only Odin is required, the rest is optional

* Odin - https://odin-lang.org/
* (Optional) Make
  * Windows GNU make - https://gnuwin32.sourceforge.net/packages/make.htm


## Quick start

To include the library in your project just copy the `metaimage` package directory containing the `metaimage.odin` file into your project and import the package like so:

```odin
import "metaimage"
```

## Usage

To load an image use `metaimage.read`. To write an image use `metaimage.write`. Small test MetaImage files (.mha/.mhd) can be found in this repository under `./tests/res`.

The following example demonstrates both:

```odin
package example

import "core:fmt"

import "metaimage"


main :: proc () {
    input_image_filename := "tests/res/test_001.mhd"
    output_image_filename := "output_image.mha"

    // Read input image
    img, err := metaimage.read(input_image_filename)
    if err != nil {
        fmt.printf("Something went wrong loading the image %s: %v", input_image_filename, err)
        return
    }
    defer metaimage.destroy(img)

    // Show some image information
    fmt.printfln("Image was succesfully loaded: %s", input_image_filename)
    fmt.printfln("  Image dimensions : %v", img.DimSize)
    fmt.printfln("  Data type        : %v", img.ElementType)
    fmt.printfln("  Spacing          : %v", img.ElementSpacing)
    fmt.printfln("  Origin           : %v", img.Offset)
    fmt.printfln("  Direction        : %v", img.TransformMatrix)
    fmt.printfln("  Was Compressed   : %t", img.CompressedData)
    if img.CompressedData {
        fmt.printfln("  Compressed size  : %d", img.CompressedDataSize)
    }

    // Do something with the actual image data
    // img.Data

    // Write image to another file
    assert(
        input_image_filename != output_image_filename,
        "output filename is the same as the input filename, this would overwrite the source file!"
    )
    write_err := metaimage.write(
        img=img,
        filename=output_image_filename,
        compression=true
    )
    if write_err != nil {
        fmt.printf("Something went wrong writing the image %s: %v", output_image_filename, write_err)
        return
    }
}
```

## Example

This repository also has an extended example file: `example.odin`.
To build and run this example run:

```bash
make run
```

Which is roughly equivalent to:
```bash
odin run . -disable-assert -no-bounds-check -o:speed
```


or for a debug build and run:

```bash
make debug
```

Which is roughly equivalent to:
```bash
odin run . -debug
```


## Tests

To build and run the tests run:

```bash
make test
```

Which is roughly equivalent to:
```bash
odin test ./tests
```
