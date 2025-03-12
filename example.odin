/* Example for working with the MetaIO Odin package
*
* Author: Sil van de Leemput
* email: sil.vandeleemput@radboudumc.nl
*/

package example

import "core:os"
import "core:time"
import "core:fmt"

import "metaio"


main :: proc()
{
    input_test_image_file := `.\tests\res\test_001.mhd`
    output_test_image_file := `.\tests\res\test_001_compressed_write_test.mhd`

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
    img, err := metaio.image_read(input_test_image_file, allocator=context.allocator)
    if err != nil {
        fmt.printfln("Failed to read image, with error: %v", err)
        return
    }
    defer metaio.image_destroy(img=img, allocator=context.allocator)
    duration := time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for reading image: %d", duration)

    // Write image
    start_tick = time.tick_now()
    write_err := metaio.image_write(
        img=img,
        filename=output_test_image_file,
        compression=true
    )
    if write_err != nil {
        fmt.printfln("Failed to write file to %s with error: %v", output_test_image_file, write_err)
        return
    }
    duration = time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for writing image: %d", duration)

    // Read written image
    start_tick = time.tick_now()
    img2, err2 := metaio.image_read(output_test_image_file, allocator=context.allocator)
    if err2 != nil {
        fmt.printfln("Failed to read image, with error: %v", err2)
        return
    }
    defer metaio.image_destroy(img=img2, allocator=context.allocator)
    assert(err2 == nil)
    duration = time.tick_since(start_tick)
    free_all(context.temp_allocator)
    fmt.printfln("Time for reading written image: %d", duration)
    if img2.CompressedData {
        fmt.printfln(
            "Data size after compression: %d / %d (%f %%)",
            img2.CompressedDataSize,
            len(img.Data),
            f32(img2.CompressedDataSize) * 100.0 / f32(metaio.image_required_data_size(img2))
        )
    }
}
