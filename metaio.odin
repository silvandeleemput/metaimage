/* Odin package for reading and writing ITK MetaIO Image files
*
* image_read
* image_write
*
* Author: Sil van de Leemput
* email: sil.vandeleemput@radboudumc.nl
*/

package metaio

import "core:os"
import "core:os/os2"
import "core:fmt"
import "core:strings"
import "core:testing"
import "core:slice"
import "core:io"
import "core:bufio"
import "core:compress"
import "core:mem"
import "core:strconv"
import "core:path/filepath"
import "core:bytes"
import "core:time"

import "vendor:zlib"


// These imports are for runtime profiling using spall
import "core:prof/spall"
import "base:runtime"
import "core:/sync"


SPALL_ENABLED :: false


ObjectType :: enum u8 {
    Image
}


ElementType :: enum u8 {
   MET_NONE,
   MET_ASCII_CHAR,
   MET_CHAR,
   MET_UCHAR,
   MET_SHORT,
   MET_USHORT,
   MET_INT,
   MET_UINT,
   MET_LONG,
   MET_ULONG,
   MET_LONG_LONG,
   MET_ULONG_LONG,
   MET_FLOAT,
   MET_DOUBLE,
   MET_STRING,
   MET_CHAR_ARRAY,
   MET_UCHAR_ARRAY,
   MET_SHORT_ARRAY,
   MET_USHORT_ARRAY,
   MET_INT_ARRAY,
   MET_UINT_ARRAY,
   MET_LONG_ARRAY,
   MET_ULONG_ARRAY,
   MET_LONG_LONG_ARRAY,
   MET_ULONG_LONG_ARRAY,
   MET_FLOAT_ARRAY,
   MET_DOUBLE_ARRAY,
   MET_FLOAT_MATRIX,
   MET_OTHER
}


MET_ValueTypeSize :: [ElementType]u8 {
   .MET_NONE = 0,
   .MET_ASCII_CHAR = 1,
   .MET_CHAR = 1,
   .MET_UCHAR = 1,
   .MET_SHORT = 2,
   .MET_USHORT = 2,
   .MET_INT = 4,
   .MET_UINT = 4,
   .MET_LONG = 4,
   .MET_ULONG = 4,
   .MET_LONG_LONG = 8,
   .MET_ULONG_LONG = 8,
   .MET_FLOAT = 4,
   .MET_DOUBLE = 8,
   .MET_STRING = 1,
   .MET_CHAR_ARRAY = 1,
   .MET_UCHAR_ARRAY = 1,
   .MET_SHORT_ARRAY = 2,
   .MET_USHORT_ARRAY = 2,
   .MET_INT_ARRAY = 4,
   .MET_UINT_ARRAY = 4,
   .MET_LONG_ARRAY = 4,
   .MET_ULONG_ARRAY = 4,
   .MET_LONG_LONG_ARRAY = 8,
   .MET_ULONG_LONG_ARRAY = 8,
   .MET_FLOAT_ARRAY = 4,
   .MET_DOUBLE_ARRAY = 8,
   .MET_FLOAT_MATRIX = 4,
   .MET_OTHER = 0,
}


MET_MaxChunkSize :: 1024 * 1024 * 1024  // 2 ^ 30 Used for zlib compression/decompression, must be less than 2 ^ 32!


Image :: struct {
    ObjectType: ObjectType,
    NDims: u8,
    ElementType: ElementType,
    ElementNumberOfChannels: u8,
    CompressedData: bool,
    BinaryData: bool,
    BinaryDataByteOrderMSB: bool,
    CompressedDataSize: u64,
    DimSize: []u16,
    Offset: []f64,
    ElementSpacing: []f64,
    TransformMatrix: []f64,
    ElementDataFile: string,
    MetaData: map [string]string,
    Data: []byte,
}


ZLIB_Error :: enum i8 {
    OK = 0,
    STREAM_END = 1,
    NEED_DICT = 2,
    ERRNO = -1,
    STREAM_ERROR = -2,
    DATA_ERROR = -3,
    MEM_ERROR = -4,
    BUF_ERROR = -5,
    VERSION_ERROR = -6,
}


Error :: union {
    os.Error,
    os.General_Error,
    io.Error,
    os.Platform_Error,
    mem.Allocator_Error,
    ZLIB_Error,
}


create_f64_array :: proc(elements_string: string, n_elements: int, allocator:= context.allocator) -> (a: []f64, error: Error) {
    sub_values := strings.split(s=elements_string, sep=" ", allocator=context.temp_allocator) or_return
    arr := make([]f64, n_elements, allocator=allocator) or_return
    assert(len(sub_values) == n_elements)
    for i in 0..<n_elements {
        n, parse_ok := strconv.parse_f64(str=sub_values[i])
        ensure(parse_ok)
        arr[i] = n
    }
    return arr[:], nil
}


create_u16_array :: proc(elements_string: string, n_elements: int, allocator:= context.allocator) -> (a: []u16, error: Error) {
    sub_values := strings.split(s=elements_string, sep=" ", allocator=context.temp_allocator) or_return
    arr := mem.make([]u16, n_elements, allocator=allocator) or_return
    assert(len(sub_values) == int(n_elements))
    for i in 0..<n_elements {
        n, parse_ok := strconv.parse_uint(s=sub_values[i])
        ensure(parse_ok)
        arr[i] = u16(n)
    }
    return arr[:], nil
}


image_required_data_size :: proc(img: Image) -> uint {
    // compute required total memory for data buffer
    assert(len(img.DimSize) > 0, "image_required_data_size, requires img.DimSize to be of non-zero length")
    total_bytes_required : = uint(img.DimSize[0])
    for val in img.DimSize[1:] {
        total_bytes_required = total_bytes_required * uint(val)
    }
    value_type_size := MET_ValueTypeSize
    total_bytes_required = total_bytes_required * uint(value_type_size[img.ElementType]) * uint(img.ElementNumberOfChannels)
    return total_bytes_required
}


image_init_header :: proc(img: ^Image) {
    // TODO init this with NDims, and allocate all required memory here etc... ???
    img.ObjectType = .Image
    img.ElementNumberOfChannels = 1
    img.NDims = 3
    img.BinaryData = true
    img.BinaryDataByteOrderMSB = false
    img.ElementType = .MET_NONE
}


image_read_header :: proc(img: ^Image, reader_stream: io.Reader, allocator := context.allocator) -> (bytes_read: int, error: Error) {
    file_buffer : [256] byte

    buffered_reader := bufio.Reader{}
    bufio.reader_init_with_buf(
        b=&buffered_reader,
        rd=reader_stream,
        buf=file_buffer[:]
    )

    // set default values
    image_init_header(img)

    // read header information first
    bytes_read = 0
    meta_data_map := make(map [string]string, allocator=allocator)
    img.MetaData = meta_data_map
    for img.ElementDataFile == "" {
        next_line := bufio.reader_read_string(&buffered_reader, '\n', allocator=context.temp_allocator) or_return
        bytes_read += len(next_line)
        splits := strings.split_n(s=next_line, n=2, sep=" = ", allocator=context.temp_allocator) or_return
        key := splits[0]
        value := splits[1][:len(splits[1]) - 1]  // remove \n character at the end
        switch key {
            case "ObjectType":
                object_type_enum, parse_ok := fmt.string_to_enum_value(ObjectType, value)
                ensure(parse_ok)
                img.ObjectType = object_type_enum
            case "BinaryData":
                img.BinaryData = value == "True"
            case "BinaryDataByteOrderMSB":
                img.BinaryDataByteOrderMSB = value == "True"
            case "NDims":
                n, parse_ok := strconv.parse_uint(s=value)
                ensure(parse_ok)
                img.NDims = u8(n)
            case "CompressedData":
                img.CompressedData = value == "True"
            case "CompressedDataSize":
                n, parse_ok := strconv.parse_u64(value)
                ensure(parse_ok)
                img.CompressedDataSize = n
            case "ElementType":
                etype, parse_ok := fmt.string_to_enum_value(ElementType, value)
                ensure(parse_ok)
                img.ElementType = etype
            case "DimSize":
                a := create_u16_array(elements_string=value, n_elements=int(img.NDims), allocator=allocator) or_return
                img.DimSize = a
            case "Offset":
                a := create_f64_array(elements_string=value, n_elements=int(img.NDims), allocator=allocator) or_return
                img.Offset = a
            case "ElementNumberOfChannels":
                n, parse_ok := strconv.parse_uint(s=value)
                ensure(parse_ok)
                img.ElementNumberOfChannels = u8(n)
            case "ElementSpacing":
                a := create_f64_array(elements_string=value, n_elements=int(img.NDims), allocator=allocator) or_return
                img.ElementSpacing = a
            case "TransformMatrix":
                a := create_f64_array(elements_string=value, n_elements=int(img.NDims * img.NDims), allocator=allocator) or_return
                img.TransformMatrix = a
            case "ElementDataFile":
                cloned_value := strings.clone(value, allocator=allocator) or_return
                img.ElementDataFile = cloned_value
            case:
                cloned_key := strings.clone(key, allocator=allocator) or_return
                cloned_value := strings.clone(value, allocator=allocator) or_return
                meta_data_map[cloned_key] = cloned_value
                img.MetaData = meta_data_map
        }
    }
    // Set the reader to the beginning of data stream...
    if img.ElementDataFile == "LOCAL" {
        io.seek(s=buffered_reader.rd, offset=i64(buffered_reader.r - buffered_reader.w), whence=.Current) or_return
    }
    return bytes_read, nil
}


image_read :: proc(filename: string, allocator := context.allocator) -> (img: Image, error: Error) {
    // open file for reading as an io.Reader Stream
    fd := os.open(filename, os.O_RDONLY) or_return
    reader_stream : io.Reader = os.stream_from_handle(fd=fd)
    defer io.close(reader_stream) // this also closes the file handle

    bytes_read := image_read_header(img=&img, reader_stream=reader_stream, allocator=allocator) or_return

    // compute required total memory for data buffer
    total_bytes_required := image_required_data_size(img)

    if img.ElementDataFile == "LOCAL" {
        if img.CompressedData {
            // use zlib to decompress
            data_buffer_size := os.file_size(fd) or_return
            data_buffer_size -= i64(bytes_read)
            data_encoded_buffer := make([]u8, data_buffer_size, context.temp_allocator) or_return
            io.read(s=reader_stream, p=data_encoded_buffer[:]) or_return
            inflated_data := data_inflate_zlib(data=data_encoded_buffer, expected_output_size=total_bytes_required) or_return
            img.Data = inflated_data
        } else {
            // allocate memory for buffer and read everything in one go
            data_buffer := make([]byte, total_bytes_required, allocator=allocator) or_return
            io.read(s=reader_stream, p=data_buffer[:]) or_return
            img.Data = data_buffer[:]
        }
    } else {
        // try to open external file to read the data from
        file_dir := filepath.dir(path=filename, allocator=context.temp_allocator)
        data_filename := fmt.aprintf("%s/%s", file_dir, img.ElementDataFile, allocator=context.temp_allocator)
        fd_data := os.open(data_filename, os.O_RDONLY) or_return
        defer os.close(fd_data)

        if img.CompressedData {
            // use zlib to decompress
            data_buffer_size := os.file_size(fd_data) or_return
            data_encoded_buffer := make([]u8, data_buffer_size, context.temp_allocator) or_return
            os.read(fd=fd_data, data=data_encoded_buffer) or_return
            inflated_data := data_inflate_zlib(data=data_encoded_buffer, expected_output_size=total_bytes_required) or_return
            img.Data = inflated_data
        } else {
            // allocate memory for buffer and read everything in one go
            data_buffer := make([]byte, total_bytes_required, allocator=allocator) or_return
            os.read(fd=fd_data, data=data_buffer) or_return
            img.Data = data_buffer[:]
        }
    }
    return img, nil
}

// these functions will allocate and free memory based on the temp_allocator of the default_context
zlib_alloc_func :: proc "c" (opaque: zlib.voidp, items: zlib.uInt, size: zlib.uInt) -> zlib.voidpf {
    context = runtime.default_context()
    res, err := mem.alloc_bytes(int(size) * int(items), allocator=context.temp_allocator)
    if err != nil {
        fmt.panicf("Found the following error for allocation: %v", err)
    }
    return raw_data(res)
}

zlib_free_func :: proc "c" (opaque: zlib.voidp, address: zlib.voidpf)
{
    context = runtime.default_context()
    err := mem.free(address, allocator=context.temp_allocator)
    if err != nil && err != .Mode_Not_Implemented {  // if not implemented allow running it anyway for e.g. arena allocators
        fmt.panicf("Found the following error for freeing: %v", err)
    }
    return
}

data_inflate_zlib :: proc(data: []u8, expected_output_size: uint, allocator:=context.allocator) -> (inflated_data: []u8, err: Error) {
    // Using vendor zlib here, as it is way faster than the compress.zlib odin version
    // Using vender zlib we can also skip the Adler32 checksum, which is very time consuming for large files
    // We implement chunk size buffering like in ITK to prevent zlib issues with 32 bit c.uint and c.ulong on very large files...
    // See for reference implementation: https://github.com/Kitware/MetaIO/blob/56c9257467fa901e51e67ca5934711869ed84e49/src/metaUtils.cxx#L714
    uncompressed_data := make([]byte, expected_output_size, allocator=allocator) or_return

    strm : zlib.z_stream_s
    strm.zalloc = zlib_alloc_func // use nil for default zlib alloc func
    strm.zfree = zlib_free_func // use nil for default zlib free func
    strm.opaque = nil
    strm.avail_out = 0 // set this explicitly

    zlib_err := zlib.inflateInit2(strm=&strm, windowBits=15 + 32) // 47 - allow both gzip and zlib compression headers
    if zlib_err != zlib.OK {
        return nil, ZLIB_Error(zlib_err)
    }

    source_pos : u64 = 0
    dest_pos : u64 = 0
    zlib_err = 0

    for zlib_err != zlib.STREAM_END && zlib_err >= 0 {
        strm.next_in = &data[source_pos]
        strm.avail_in = u32(min(u64(len(data)) - source_pos, MET_MaxChunkSize))
        source_pos += u64(strm.avail_in)
        for strm.avail_out == 0 {
            cur_remain_chunk := min(u64(len(uncompressed_data)) - dest_pos, MET_MaxChunkSize)
            strm.next_out = &uncompressed_data[dest_pos]
            strm.avail_out = u32(cur_remain_chunk)
            zlib_err = zlib.inflate(strm=&strm, flush=zlib.NO_FLUSH)
            if zlib_err == zlib.STREAM_END || zlib_err < 0
            {
                if zlib_err != zlib.STREAM_END && zlib_err != zlib.BUF_ERROR {
                    // Z_BUF_ERROR means there is still data to uncompress,
                    // but no space left in buffer; non-fatal
                    fmt.printf("Decompress failed with %d", ZLIB_Error(zlib_err))
                }
                // added additional count check here on stream end to be able to verify inflated data size matches the expected_output_size
                if zlib_err == zlib.STREAM_END {
                    count_uncompressed := cur_remain_chunk - u64(strm.avail_out)
                    dest_pos += count_uncompressed
                }
                break
            }
            count_uncompressed := cur_remain_chunk - u64(strm.avail_out)
            dest_pos += count_uncompressed
        }
    }
    zlib_err = zlib.inflateEnd(strm=&strm)
    if zlib_err != zlib.OK {
        return nil, ZLIB_Error(zlib_err)
    }
    assert(expected_output_size == uint(dest_pos), fmt.aprintf("expected: %d,  got: %d", expected_output_size, dest_pos, allocator=context.temp_allocator))
    return uncompressed_data[:expected_output_size], nil
}

data_deflate_zlib :: proc(data: []u8, allocator:=context.allocator) -> (deflated_data: []u8, compressed_data_size: u64, err: Error) {
    // Using vendor zlib here as there is no odin version implemented yet for deflate
    // This implementation allocates more output memory if required (for small images)...
    // We implement chunk size buffering like in ITK to prevent zlib issues with 32 bit c.uint and c.ulong on very large files...
    // See for reference implementation: https://github.com/Kitware/MetaIO/blob/56c9257467fa901e51e67ca5934711869ed84e49/src/metaUtils.cxx#L714

    strm : zlib.z_stream_s
    strm.zalloc = zlib_alloc_func // use nil for default zlib alloc func
    strm.zfree = zlib_free_func // use nil for default zlib free func
    strm.opaque = nil

    source_size := u64(len(data))
    buffer_out_size := source_size
    max_chunk_size := MET_MaxChunkSize
    chunk_size := u32(min(len(data), max_chunk_size))
    input_buffer := raw_data(data)
    output_buffer := make([]u8, chunk_size, allocator=allocator) or_return

    compressed_data := make([]u8, buffer_out_size, allocator=allocator) or_return


    // ZLIB_MEM_LEVEL :: 8
    // ZLIB_DEF_WBITS :: 15 //+ 32
    // zlib_err := zlib.deflateInit2(
    //     strm=&strm,
    //     level=zlib.BEST_SPEED,
    //     method=zlib.DEFLATED,
    //     windowBits=ZLIB_DEF_WBITS,
    //     memLevel=ZLIB_MEM_LEVEL,
    //     strategy=zlib.FILTERED
    // )
    zlib_err := zlib.deflateInit(
        strm=&strm,
        level=zlib.BEST_SPEED
    )
    if zlib_err != zlib.OK {
        return nil, 0, ZLIB_Error(zlib_err)
    }

    cur_in_start : u64 = 0
    cur_out_start : u64 = 0
    flush : i32 = 0

    for flush != zlib.FINISH {
        strm.avail_in = u32(min(source_size - cur_in_start, u64(chunk_size)))
        strm.next_in = &input_buffer[cur_in_start]
        last_chunk := cur_in_start + u64(strm.avail_in) >= u64(len(data))
        flush = last_chunk ? zlib.FINISH : zlib.NO_FLUSH
        cur_in_start += u64(strm.avail_in)
        for strm.avail_out == 0 {
            strm.avail_out = chunk_size
            strm.next_out = raw_data(output_buffer)
            zlib_err = zlib.deflate(strm=&strm, flush=flush)
            if (zlib_err == zlib.STREAM_ERROR) {
                return nil, 0, ZLIB_Error(zlib_err)
            }
            count_out := u64(chunk_size) - u64(strm.avail_out)
            if (cur_out_start + count_out) >= buffer_out_size {
                // if we don't have enough allocation for the output buffer
                // when the output is bigger than the input (true for small images)
                compressed_data_temp := make([]u8, cur_out_start + count_out + 1, allocator=allocator) or_return
                mem.copy(raw_data(compressed_data_temp), raw_data(compressed_data), int(buffer_out_size))
                mem_err := delete(compressed_data, allocator=allocator)
                if mem_err != nil && mem_err != .Mode_Not_Implemented {
                    return nil, 0, mem_err
                }
                compressed_data = compressed_data_temp;
                buffer_out_size = cur_out_start + count_out + 1;
            }
            mem.copy(&compressed_data[cur_out_start], raw_data(output_buffer), int(count_out))
            cur_out_start += count_out
        }
    }

    compressed_data_size = cur_out_start

    mem_err := delete(output_buffer, allocator=allocator)
    if mem_err != nil && mem_err != .Mode_Not_Implemented {
        return nil, 0, mem_err
    }

    zlib_err = zlib.deflateEnd(strm=&strm)
    if zlib_err != zlib.OK {
        return nil, 0, ZLIB_Error(zlib_err)
    }

    return compressed_data[:compressed_data_size], compressed_data_size, nil
}


image_write :: proc(img: Image, filename: string, compression: bool = false, allocator:=context.temp_allocator) -> (err: Error) {
    // TODO implement atomic rename trick for intermediate writing...?
    is_single_file := strings.ends_with(filename, ".mha")
    ensure(is_single_file || strings.ends_with(filename, ".mhd"))
    element_data_file : string = "LOCAL"

    // perform zlib deflate in buffer if compression is enabled
    // (do this first to retrieve the correct compressed_data_size)
    compressed_data_size : u64
    compressed_data_buffer : []u8
    if compression {
        compressed_data_buffer, compressed_data_size = data_deflate_zlib(data=img.Data, allocator=allocator) or_return
    }
    defer if compression { delete(compressed_data_buffer, allocator=allocator) }

    // if not a single file write data to element_data_file instead
    if !is_single_file {
        element_data_file = strings.concatenate({filename[:len(filename) - 3], (compression ? "zraw" : "raw")}, allocator=allocator)
        err_open : os.Error
        fd_data := os.open(element_data_file, os.O_WRONLY|os.O_CREATE|os.O_TRUNC) or_return
        defer os.close(fd_data)
        // write the data compressed or uncompressed
        if compression {
            os.write(fd_data, compressed_data_buffer[:])
        } else {
            os.write(fd_data, img.Data)
        }
    }

    // create/open/truncate header file
    fd := os.open(filename, os.O_WRONLY|os.O_CREATE|os.O_TRUNC) or_return
    defer os.close(fd)

    objecttype_str, element_type_str : string
    parse_ok : bool
    objecttype_str, parse_ok = fmt.enum_value_to_string(img.ObjectType)
    ensure(parse_ok)
    element_type_str, parse_ok = fmt.enum_value_to_string(img.ElementType)
    ensure(parse_ok)

    to_bool_str :: proc(val: bool) -> string {
        return val ? "True" : "False"
    }

    os.write_string(fd, fmt.aprintfln("ObjectType = %v", objecttype_str, allocator=allocator))
    os.write_string(fd, fmt.aprintfln("NDims = %d", img.NDims, allocator=allocator))
    os.write_string(fd, fmt.aprintfln("BinaryData = %v", to_bool_str(img.BinaryData), allocator=allocator))
    os.write_string(fd, fmt.aprintfln("BinaryDataByteOrderMSB = %v", to_bool_str(img.BinaryDataByteOrderMSB), allocator=allocator))
    os.write_string(fd, fmt.aprintfln("CompressedData = %v", to_bool_str(compression), allocator=allocator))
    if compression {
        assert(compressed_data_size > 0)
        os.write_string(fd, fmt.aprintfln("CompressedDataSize = %d", compressed_data_size, allocator=allocator))
    }

    iterate_values_and_write :: proc(fd: os.Handle, data: []$T, allocator:=context.allocator) {
        for e in data {
            os.write_string(fd, fmt.aprintf(" %v", e, allocator=allocator))
        }
        os.write_string(fd, "\n")
    }

    os.write_string(fd, "TransformMatrix =")
    iterate_values_and_write(fd, img.TransformMatrix, allocator=allocator)
    os.write_string(fd, "Offset =")
    iterate_values_and_write(fd, img.Offset, allocator=allocator)

    // write metadata
    for k, v in img.MetaData {
        os.write_string(fd, k)
        os.write_string(fd, " = ")
        os.write_string(fd, v)
        os.write_string(fd, "\n")
    }

    os.write_string(fd, "ElementSpacing =")
    iterate_values_and_write(fd, img.ElementSpacing, allocator=allocator)
    os.write_string(fd, "DimSize =")
    iterate_values_and_write(fd, img.DimSize, allocator=allocator)

    os.write_string(fd, fmt.aprintfln("ElementType = %v", element_type_str, allocator=allocator))
    os.write_string(fd, fmt.aprintfln("ElementDataFile = %v", filepath.base(element_data_file), allocator=allocator))

    if is_single_file {
        if compression {
            os.write(fd, compressed_data_buffer[:])
        } else {
            os.write(fd, img.Data)
        }
    }

    return nil
}


image_destroy :: proc(img: Image, allocator:=context.allocator) {
    delete(img.DimSize, allocator=allocator)
    delete(img.TransformMatrix, allocator=allocator)
    delete(img.ElementSpacing, allocator=allocator)
    delete(img.Offset, allocator=allocator)
    delete(img.ElementDataFile, allocator=allocator)
    for k, v in img.MetaData {
        delete(k, allocator=allocator)
        delete(v, allocator=allocator)
    }
    delete(img.MetaData)
    delete(img.Data, allocator=allocator)
}



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
    img, err := image_read(input_test_image_file, allocator=context.allocator)
    free_all(context.temp_allocator)
    duration := time.tick_since(start_tick)
    fmt.printf("Time for loading image: %d", duration)

    start_tick = time.tick_now()
    write_err := image_write(img, output_test_image_file, true)
    free_all(context.temp_allocator)
    duration = time.tick_since(start_tick)
    fmt.printf("Time for writing image: %d", duration)
    img2, err2 := image_read(output_test_image_file, allocator=context.allocator)
    fmt.printf("Data size after compression: %d / %d", img2.CompressedDataSize, len(img.Data))

    image_destroy(img, allocator=context.allocator)
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

when ODIN_DEBUG {
    @(test)
    test_image_read_compressed_mhd :: proc(t: ^testing.T) {
        test_image_read_expected_values(t=t, test_file_name=`.\test\test_001.mhd`, compressed=true)
    }

    @(test)
    test_image_read_compressed_mha :: proc(t: ^testing.T) {
        test_image_read_expected_values(t=t, test_file_name=`.\test\test_001.mha`, compressed=true)
    }

    @(test)
    test_image_read_uncompressed_mhd :: proc(t: ^testing.T) {
        test_image_read_expected_values(t=t, test_file_name=`.\test\test_001_uncompressed.mhd`, compressed=false)
    }

    @(test)
    test_image_read_uncompressed_mha :: proc(t: ^testing.T) {
        test_image_read_expected_values(t=t, test_file_name=`.\test\test_001_uncompressed.mha`, compressed=false)
    }

    @(test)
    test_image_write_uncompressed_mha :: proc(t: ^testing.T) {
        input_test_image_file := `.\test\test_001.mhd`
        output_test_image_file := `.\test\tmp_test_001_write_test.mha`
        img, err := image_read(input_test_image_file, allocator=context.allocator)
        defer image_destroy(img, allocator=context.allocator)
        free_all(context.temp_allocator)
        write_err := image_write(img, output_test_image_file, false)
        defer if os.exists(output_test_image_file) { os.unlink(output_test_image_file) }
        testing.expect(t, os.exists(input_test_image_file), fmt.aprintf("Input test file does not exist: %s", input_test_image_file, allocator=context.temp_allocator))
        testing.expect(t, os.exists(output_test_image_file), fmt.aprintf("Output test file does not exist: %s", output_test_image_file, allocator=context.temp_allocator))
        test_image_read_expected_values(t=t, test_file_name=output_test_image_file, compressed=false)
    }

    @(test)
    test_image_write_uncompressed_mhd :: proc(t: ^testing.T) {
        input_test_image_file := `.\test\test_001.mhd`
        output_test_image_file := `.\test\tmp_test_001_write_test.mhd`
        output_test_image_data_file := `.\test\tmp_test_001_write_test.raw`
        img, err := image_read(input_test_image_file, allocator=context.allocator)
        defer image_destroy(img, allocator=context.allocator)
        free_all(context.temp_allocator)
        write_err := image_write(img, output_test_image_file, false)
        defer if os.exists(output_test_image_file) { os.unlink(output_test_image_file) }
        defer if os.exists(output_test_image_data_file) { os.unlink(output_test_image_data_file) }
        testing.expect(t, os.exists(input_test_image_file), fmt.aprintf("Input test file does not exist: %s", input_test_image_file, allocator=context.temp_allocator))
        testing.expect(t, os.exists(output_test_image_file), fmt.aprintf("Output test file does not exist: %s", output_test_image_file, allocator=context.temp_allocator))
        testing.expect(t, os.exists(output_test_image_data_file), fmt.aprintf("Output test data file does not exist: %s", output_test_image_data_file, allocator=context.temp_allocator))
        test_image_read_expected_values(t=t, test_file_name=output_test_image_file, compressed=false)
    }

    @(test)
    test_image_write_compressed_mha :: proc(t: ^testing.T) {
        input_test_image_file := `.\test\test_001.mhd`
        output_test_image_file := `.\test\tmp_test_001_write_test_c.mha`
        img, err := image_read(input_test_image_file, allocator=context.allocator)
        testing.expect(t, err == nil, fmt.aprintf("\nFOUND READ ERROR: %v", err, allocator=context.temp_allocator))
        if err != nil {
            return
        }
        defer image_destroy(img, allocator=context.allocator)
        free_all(context.temp_allocator)
        write_err := image_write(img, output_test_image_file, true)
        testing.expect(t, write_err == nil, fmt.aprintf("\nFOUND WRITE ERROR: %v", write_err, allocator=context.temp_allocator))
        if write_err != nil {
            return
        }
        defer if os.exists(output_test_image_file) { os.unlink(output_test_image_file) }
        testing.expect(t, os.exists(input_test_image_file), fmt.aprintf("Input test file does not exist: %s", input_test_image_file, allocator=context.temp_allocator))
        testing.expect(t, os.exists(output_test_image_file), fmt.aprintf("Output test file does not exist: %s", output_test_image_file, allocator=context.temp_allocator))
        test_image_read_expected_values(t=t, test_file_name=output_test_image_file, compressed=true)
    }

    @(test)
    test_image_write_compressed_mhd :: proc(t: ^testing.T) {
        input_test_image_file := `.\test\test_001.mhd`
        output_test_image_file := `.\test\tmp_test_001_write_test_c.mhd`
        output_test_image_data_file := `.\test\tmp_test_001_write_test_c.zraw`
        img, err := image_read(input_test_image_file, allocator=context.allocator)
        testing.expect(t, err == nil, fmt.aprintf("\nFOUND READ ERROR: %v", err, allocator=context.temp_allocator))
        if err != nil {
            return
        }
        defer image_destroy(img, allocator=context.allocator)
        free_all(context.temp_allocator)
        write_err := image_write(img, output_test_image_file, true)
        testing.expect(t, write_err == nil, fmt.aprintf("\nFOUND WRITE ERROR: %v", write_err, allocator=context.temp_allocator))
        if write_err != nil {
            return
        }
        defer if os.exists(output_test_image_file) { os.unlink(output_test_image_file) }
        defer if os.exists(output_test_image_data_file) { os.unlink(output_test_image_data_file) }
        testing.expect(t, os.exists(input_test_image_file), fmt.aprintf("Input test file does not exist: %s", input_test_image_file, allocator=context.temp_allocator))
        testing.expect(t, os.exists(output_test_image_file), fmt.aprintf("Output test file does not exist: %s", output_test_image_file, allocator=context.temp_allocator))
        testing.expect(t, os.exists(output_test_image_data_file), fmt.aprintf("Output test data file does not exist: %s", output_test_image_data_file, allocator=context.temp_allocator))
        test_image_read_expected_values(t=t, test_file_name=output_test_image_file, compressed=true)
    }


    test_image_read_expected_values :: proc(t: ^testing.T, test_file_name: string, compressed: bool) {
        // TODO replace tests with smaller test files...
        img, err := image_read(test_file_name, allocator=context.allocator)
        defer image_destroy(img, allocator=context.allocator)
        free_all(context.temp_allocator)

        EXPECTED_NDIMS :: 3
        EXPECTED_DIM_SIZES : []u16 : {1024, 1024, 343}
        EXPECTED_ELEMENT_SPACING : []f64 : {0.3910059928894043, 0.3910059928894043, 1}
        EXPECTED_OFFSET: []f64 : {-184.37481689453125, -199.99981689453125, 1378}
        EXPECTED_TRANSFORM_MATRIX: []f64 : {1, 0, 0, 0, 1, 0, 0, 0, 1}
        // fmt.printf("%v ", img)

        testing.expect(t, os.exists(test_file_name), fmt.aprintf("Test file does not exist: %s", test_file_name, allocator=context.temp_allocator))
        testing.expect(t, err == nil, fmt.aprintf("load_image method should return nil, found %v", err, allocator=context.temp_allocator))
        testing.expect(t, img.ObjectType == .Image, "Image ObjectType should match Image")
        testing.expect(t, img.NDims == EXPECTED_NDIMS, fmt.aprintf("Image ndims size should be %d", EXPECTED_NDIMS, allocator=context.temp_allocator))
        testing.expect(t, img.BinaryData, "Image BinaryData should be True")
        testing.expect(t, !img.BinaryDataByteOrderMSB, "Image BinaryDataByteOrderMSB should be False")
        testing.expect(t, slice.equal(img.DimSize, EXPECTED_DIM_SIZES), fmt.aprintf("Image DimSize should match: %v found %v", EXPECTED_DIM_SIZES, img.DimSize, allocator=context.temp_allocator))
        testing.expect(t, slice.equal(img.Offset, EXPECTED_OFFSET), fmt.aprintf("Image Offset should match: %v", EXPECTED_OFFSET, allocator=context.temp_allocator))
        testing.expect(t, slice.equal(img.ElementSpacing, EXPECTED_ELEMENT_SPACING), fmt.aprintf("Image ElementSpacing should match: %v", EXPECTED_ELEMENT_SPACING, allocator=context.temp_allocator))
        testing.expect(t, slice.equal(img.TransformMatrix, EXPECTED_TRANSFORM_MATRIX), fmt.aprintf("Image TransformMatrix should match: %v", EXPECTED_TRANSFORM_MATRIX, allocator=context.temp_allocator))
        testing.expect(t, img.ElementType == .MET_UCHAR, "Image ElementType should match MET_UCHAR")
        testing.expect(t, img.CompressedData == compressed, fmt.aprintf("Image CompressedData should be %v", compressed, allocator=context.temp_allocator))
        if compressed {
            //expected_compressed_data_size := u64(strings.ends_with(test_file_name, ".mha") ? 1702408 : 1405133)
            expected_compressed_sizes : []u64 = {1702408, 1405133, 2986855}
            testing.expect(t, slice.contains(expected_compressed_sizes, img.CompressedDataSize), fmt.aprintf("Image CompressedDataSize should be any of %d, found %d", expected_compressed_sizes, img.CompressedDataSize, allocator=context.temp_allocator))
        }

        // test meta data (for 3 test images has weird additional ITK_* tags that can be ignored)
        testing.expect(t, len(img.MetaData) == 2 || len(img.MetaData) == 5, fmt.aprintf("Found unexpected number of metadata %d != 2", len(img.MetaData), allocator=context.temp_allocator))
        testing.expect(t, ("AnatomicalOrientation" in img.MetaData) && img.MetaData["AnatomicalOrientation"] == "RAI", "MetaData key AnatomicalOrientation was found to be incorrect")
        testing.expect(t, ("CenterOfRotation" in img.MetaData) && img.MetaData["CenterOfRotation"] == "0 0 0", "MetaData key CenterOfRotation was found to be incorrect")

        expected_element_data_file := strings.concatenate({filepath.base(test_file_name[:len(test_file_name) - 3]), (compressed ? "zraw" : "raw")}, allocator=context.temp_allocator)
        expected_element_data_file = strings.ends_with(test_file_name, ".mha") ? "LOCAL" : expected_element_data_file
        testing.expect(t, img.ElementDataFile == expected_element_data_file, fmt.aprintf("Image ElementDataFile should be equal to `%s`", expected_element_data_file, allocator=context.temp_allocator))

        unexpected_values, total_voxels, total_sum : uint = 0, 0, 0
        for data_element in img.Data {
            if data_element != 0 && data_element != 3 {
                unexpected_values += 1
            }
            total_sum += uint(data_element)
            total_voxels += 1
        }
        testing.expect(t, unexpected_values == 0, "Found unexpected values in the test data")
        testing.expect(t, total_voxels == 359661568, "Found unexpected number of voxels in the test data")
        testing.expect(t, image_required_data_size(img) == total_voxels, fmt.aprintf("Found data_size (%d) != than the total number of voxels (%d)", image_required_data_size(img), total_voxels, allocator=context.temp_allocator))
        testing.expect(t, total_sum == 115079760, "Found unexpected total sum in the test data")
    }
}
