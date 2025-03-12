/* Example for working with the metaio Odin package
*
* Author: Sil van de Leemput
* email: sil.vandeleemput@radboudumc.nl
*/

package example

import "core:os"
import "core:time"
import "core:fmt"

import "metaio"

// These imports are for runtime profiling using spall
import "core:prof/spall"
import "base:runtime"
import "core:/sync"


SPALL_ENABLED :: false



main :: proc()
{
    when SPALL_ENABLED {
        // Inject Spall runtime profiling...
        spall_ctx = spall.context_create("metaio_trace.spall")
        defer spall.context_destroy(&spall_ctx)

        buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
        defer delete(buffer_backing)

        spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
        defer spall.buffer_destroy(&spall_ctx, &spall_buffer)

        spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
    }


    input_test_image_file := `.\test\test_001.mhd`
    //input_test_image_file := `D:\data\large_nodule_test\gclarge\input\images\fixed\large.mhd`
    if len(os.args) > 1 {
        input_test_image_file = os.args[1]
        fmt.printf("Opening %s", input_test_image_file)
        if !os.exists(input_test_image_file) {
            fmt.printf("Could not find the file %s", input_test_image_file)
            return
        }
    }

    output_test_image_file := `.\test\test_001_compressed_write_test.mhd`

    start_tick := time.tick_now()
    img, err := metaio.image_read(input_test_image_file, allocator=context.allocator)
    free_all(context.temp_allocator)
    duration := time.tick_since(start_tick)
    fmt.printf("Time for loading image: %d", duration)

    start_tick = time.tick_now()
    write_err := metaio.image_write(img, output_test_image_file, true)
    free_all(context.temp_allocator)
    duration = time.tick_since(start_tick)
    fmt.printf("Time for writing image: %d", duration)
    img2, err2 := metaio.image_read(output_test_image_file, allocator=context.allocator)
    fmt.printf("Data size after compression: %d / %d", img2.CompressedDataSize, len(img.Data))

    metaio.image_destroy(img, allocator=context.allocator)
}


when SPALL_ENABLED {
    spall_ctx: spall.Context
    @(thread_local) spall_buffer: spall.Buffer

    @(instrumentation_enter)
    spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
        spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
    }

    @(instrumentation_exit)
    spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
        spall._buffer_end(&spall_ctx, &spall_buffer)
    }
}
