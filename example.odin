/* Example using the the MetaImage Odin package
*
* Author: Sil van de Leemput
* email: sil.vandeleemput@radboudumc.nl
*/

package example

import "core:os"
import "core:time"
import "core:fmt"
import "core:strings"

import "metaimage"


main :: proc()
{
    // Set the default filepath to the input image to use and a filepath to an output image
    input_image_filepath := `./tests/res/test_002.mha`
    output_image_filepath := `./tmp_write_test.mhd`

    // Default input and output images can be overriden by providing command line arguments
    if len(os.args) > 1 {
        input_image_filepath = os.args[1]
    }
    if len(os.args) > 2 {
        output_image_filepath = os.args[2]
    }

    // Read input image
    fmt.printfln("Reading %s", input_image_filepath)
    if !os.exists(input_image_filepath) {
        fmt.printfln("Could not find the file %s", input_image_filepath)
        return
    }
    start_tick := time.tick_now()
    input_image, err := metaimage.read(filename=input_image_filepath, allocator=context.allocator)
    if err != nil {
        fmt.printfln("Failed to read image, with error: %v", err)
        return
    }
    defer metaimage.destroy(img=input_image, allocator=context.allocator)
    free_all(context.temp_allocator)
    if len(input_image.Data) < 100 {
        fmt.printfln("%v", input_image)
    }
    duration := time.tick_since(start_tick)
    fmt.printfln("Time for reading image: %d", duration)


    // Write output image
    start_tick = time.tick_now()
    write_err := metaimage.write(
        img=input_image,
        filename=output_image_filepath,
        compression=true,
        compression_options=metaimage.FAST_COMPRESSION_OPTIONS,
        allocator=context.temp_allocator
    )
    if write_err != nil {
        fmt.printfln("Failed to write file to %s with error: %v", output_image_filepath, write_err)
        return
    }
    // cleanup generated files
    defer {
        if os.exists(output_image_filepath) do os.remove(output_image_filepath)
        exts : [2]string = {"raw", "zraw"}
        for data_ext in exts {
            output_data_file := strings.concatenate({output_image_filepath[:len(output_image_filepath)-3], data_ext}, allocator=context.temp_allocator)
            if os.exists(output_data_file) do os.remove(output_data_file)
        }
    }
    duration = time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for writing image: %d", duration)


    // Read output image
    start_tick = time.tick_now()
    output_image, err_read_img2 := metaimage.read(filename=output_image_filepath, allocator=context.allocator)
    if err_read_img2 != nil {
        fmt.printfln("Failed to read image, with error: %v", err_read_img2)
        return
    }
    defer metaimage.destroy(img=output_image, allocator=context.allocator)
    duration = time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for reading output image: %d", duration)
    if output_image.CompressedData {
        req_data_size := metaimage.required_data_size(output_image)
        fmt.printfln(
            "Data size after compression: %d / %d (%f %%) bytes",
            output_image.CompressedDataSize,
            req_data_size,
            f32(output_image.CompressedDataSize) * 100.0 / f32(req_data_size)
        )
    }
}
