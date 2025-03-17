# MetaImage Odin library

A simple and lightweight Odin lang library for reading and writing the ITK MetaImage file format.
 The library implements a small subset of the ITK MetaIO features with a strong focus on MetaImage objects.

ITK MetaImage documentation: 
https://itk.org/Wiki/ITK/MetaIO/Documentation#MetaImage

## Features
* Support for reading and writing (.mha) and (.mhd/.raw/.zraw) MetaImage formats
* Support for zlib compression/decompression using vendor:zlib
  * Support for custom compression options using metaio.ZLIBCompressionOptions struct
* Support for file and stream IO
* Support for metadata in a string:string dictionary (img.MetaData)
* Tests for core functionality under Windows and Linux

## Disclaimer

I created this library in my spare time and it's my first Odin project. Suggestions or improvements are welcome. Although the main functionality of the library is covered by tests, use at your own risk!

### Limitations
* No support for MetaImage files with multiple external data files
* ObjectType only supports Image
* Some MetaObject tags and their associated values are not explicitly supported. However, when present in the header they will be available in the MetaData dict (img.MetaData) as string:string pairs


## Prerequisites

On Windows it might be nice to use the GNU make program, but it is not required.
* https://gnuwin32.sourceforge.net/packages/make.htm


## Quick start

To include in your project just copy the `metaimage` package directory into your project and import the package like so:

```odin
import "metaimage"
```

To load an image use `metaimage.read` and to write an image use `metaimage.write` as shown in the following simple example:

```odin
package example

import "core:fmt"

import "metaimage"


main :: proc () {
    input_image_filename := "image.mhd"
    output_image_filename := "output_image.mha"

    img, err := metaimage.read(input_image_filename)
    if err != nil {
        fmt.printf("Something went wrong loading the image %s: %v", input_image_filename, err)
        return
    }
    defer metaimage.destroy(img)

    write_err := metaimage.write(
        img=img,
        name=output_image_filename,
        compression=true
    )
    if write_err != nil {
        fmt.printf("Something went wrong writing the image %s: %v", output_image_filename, write_err)
        return
    }
}
```

## Example

This repository also comes with a bit more elaborate example `example.odin`
To build and run the example run:

```bash
make run
```

or

```bash
make debug
```

for a debug build with debug symbols.

## Tests

To build and run the tests run:

```bash
make test
```


