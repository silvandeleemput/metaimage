/* Example for working with the MetaIO Odin package
*
* Author: Sil van de Leemput
* email: sil.vandeleemput@radboudumc.nl
*/

package example

import "core:os"
import "core:time"
import "core:fmt"
import "core:strings"

import "metaio"


main :: proc()
{
    input_test_image_file := `.\tests\res\test_002.mha`
    output_test_image_file := `.\tmp_write_test.mhd`

    if len(os.args) > 1 {
        input_test_image_file = os.args[1]
    }
    if len(os.args) > 2 {
        output_test_image_file = os.args[2]
    }

    // Read image
    fmt.printfln("Reading %s", input_test_image_file)
    if !os.exists(input_test_image_file) {
        fmt.printfln("Could not find the file %s", input_test_image_file)
        return
    }
    start_tick := time.tick_now()
    input_image, err := metaio.image_read(filename=input_test_image_file, allocator=context.allocator)
    if err != nil {
        fmt.printfln("Failed to read image, with error: %v", err)
        return
    }
    defer metaio.image_destroy(img=input_image, allocator=context.allocator)
    if len(input_image.Data) < 100 {
        fmt.printfln("%v", input_image)
    }
    duration := time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for reading image: %d", duration)

    // Write image
    start_tick = time.tick_now()
    write_err := metaio.image_write(
        img=input_image,
        filename=output_test_image_file,
        compression=true,
        compression_options=metaio.FAST_COMPRESSION_OPTIONS
    )
    if write_err != nil {
        fmt.printfln("Failed to write file to %s with error: %v", output_test_image_file, write_err)
        return
    }
    // cleanup generated files
    defer {
        if os.exists(output_test_image_file) do os.unlink(output_test_image_file)
        exts : [2]string = {"raw", "zraw"}
        for data_ext in exts {
            output_data_file := strings.concatenate({output_test_image_file[:len(output_test_image_file)-3], data_ext}, allocator=context.temp_allocator)
            if os.exists(output_data_file) do os.unlink(output_data_file)
        }
    }
    duration = time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for writing image: %d", duration)

    // Read written image
    start_tick = time.tick_now()
    output_image, err_read_img2 := metaio.image_read(filename=output_test_image_file, allocator=context.allocator)
    if err_read_img2 != nil {
        fmt.printfln("Failed to read image, with error: %v", err_read_img2)
        return
    }
    defer metaio.image_destroy(img=output_image, allocator=context.allocator)
    duration = time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for reading written image: %d", duration)
    if output_image.CompressedData {
        req_data_size := metaio.image_required_data_size(output_image)
        fmt.printfln(
            "Data size after compression: %d / %d (%f %%) bytes",
            output_image.CompressedDataSize,
            req_data_size,
            f32(output_image.CompressedDataSize) * 100.0 / f32(req_data_size)
        )
    }
}
