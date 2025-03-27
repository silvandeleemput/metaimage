/* Basic example code for using the the MetaImage Odin package
*
* This is a basic example for how to use the MetaImage library
*
* This example:
*   1. Reads a MetaIO image from the default provided test input files
*   2. Displays some information about the image
*   3. Writes it to `output_image.mha`
*/

package example

import "core:fmt"

import "metaimage"


main :: proc () {
    input_image_filename := "tests/res/test_001.mhd"
    output_image_filename := "output_image.mha"

    img, err := metaimage.read(input_image_filename)
    if err != nil {
        fmt.printf("Something went wrong loading the image %s: %v", input_image_filename, err)
        return
    }
    defer metaimage.destroy(img)

    // Show some image information
    fmt.printfln("Image was succesfully loaded: %s", input_image_filename)
    fmt.printfln("  Image dimensions: %v", img.DimSize)
    fmt.printfln("  Data type       : %v", img.ElementType)
    fmt.printfln("  Spacing         : %v", img.ElementSpacing)
    fmt.printfln("  Origin          : %v", img.Offset)
    fmt.printfln("  Direction       : %v", img.TransformMatrix)
    fmt.printfln("  Was Compressed  : %t", img.CompressedData)
    if img.CompressedData {
        fmt.printfln("  Compressed size : %d", img.CompressedDataSize)
    }

    // Do something with the data
    // img.Data

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
