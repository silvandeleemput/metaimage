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
import "core:mem"
import "core:strconv"
import "core:path/filepath"
import "core:compress/zlib"
import "core:bytes"


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


Error :: union {
    os.Error,
    os.General_Error,
    io.Error,
    os.Platform_Error,
    mem.Allocator_Error
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


image_required_data_size :: proc(img: Image) -> int {
    // compute required total memory for data buffer
    total_bytes_required : = int(img.DimSize[0])
    for val in img.DimSize[1:] {
        total_bytes_required = total_bytes_required * int(val)
    }
    value_type_size := MET_ValueTypeSize
    total_bytes_required = total_bytes_required * int(value_type_size[img.ElementType]) * int(img.ElementNumberOfChannels)
    return total_bytes_required
}


image_init :: proc(img: ^Image) {
    // TODO init this with NDims, and allocate all required memory here etc... ???
    img.ObjectType = .Image
    img.ElementNumberOfChannels = 1
    img.NDims = 3
    img.BinaryData = true
    img.BinaryDataByteOrderMSB = false
    img.ElementType = .MET_NONE
}


image_read :: proc(filename: string, allocator := context.allocator) -> (img: Image, error: Error) {
    // open file for reading
    fd := os.open(filename, os.O_RDONLY) or_return
    defer os.close(fd)
    file_buffer : [256] byte

    // create a buffered io.Reader Stream
    reader_stream : io.Reader = os.stream_from_handle(fd=fd)
    defer io.close(reader_stream)
    buffered_reader := bufio.Reader{}
    bufio.reader_init_with_buf(
        b=&buffered_reader,
        rd=reader_stream,
        buf=file_buffer[:]
    )

    // set default values
    image_init(&img)

    // read header information first
    bytes_read := 0
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

    // compute required total memory for data buffer
    total_bytes_required := image_required_data_size(img)


    if img.ElementDataFile == "LOCAL" {

        buffered_reader_read_until_eof :: proc(buffered_reader: bufio.Reader, buffer_dest: []u8) -> (err: Error) {
            // pretty hacky approach to extract remainder read data in buffer after the newline and copy to data_encoded_buffer
            n_unprocessed_elements_in_buffer := buffered_reader.w - buffered_reader.r
            for i in 0..<n_unprocessed_elements_in_buffer {
                buffer_dest[i] = buffered_reader.buf[i + buffered_reader.r]
            }
            // read the rest of the file directly without the buffered reader
            n := io.read(s=buffered_reader.rd, p=buffer_dest[n_unprocessed_elements_in_buffer:]) or_return

            assert(n + n_unprocessed_elements_in_buffer == len(buffer_dest))

            return nil
        }

        if img.CompressedData {
            // use zlib to decompress
            data_buffer_size := os.file_size(fd) or_return
            data_buffer_size -= i64(bytes_read)
            data_encoded_buffer := make([]u8, data_buffer_size, context.temp_allocator) or_return

            buffered_reader_read_until_eof(buffered_reader=buffered_reader, buffer_dest=data_encoded_buffer) or_return

            // TODO possible to have a stream as input for inflate???
            // compress.Context_Memory_Input
            buf: bytes.Buffer
            err := zlib.inflate_from_byte_array(input=data_encoded_buffer, buf=&buf, expected_output_size=total_bytes_required + 1) // +1 prevents dynamic buffer grow call and hence allocation of too much space...

            //defer bytes.buffer_destroy(&buf) // don't destroy, keep data around...
            img.Data = buf.buf[:total_bytes_required]
        } else {
            // allocate memory for buffer
            data_buffer := make([]byte, total_bytes_required, allocator=allocator) or_return

            // bufio.reader_read must be called in a loop until everything is consumed, this seems suboptimal, since we know the req. size
            // It appears this is expected behavior, it reads buffer size max, it must be called multiple times until reader generates a consume error...

            buffered_reader_read_until_eof(buffered_reader=buffered_reader, buffer_dest=data_buffer) or_return

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
            // defer delete(data_encoded_buffer) // this gives a bad free ( I don't understand, maybe because it is put on temp_allocator ?)
            encoded_input := os.read(fd=fd_data, data=data_encoded_buffer) or_return
            buf: bytes.Buffer
            // TODO possible to have a stream as input for inflate???
            err := zlib.inflate_from_byte_array(input=data_encoded_buffer, buf=&buf, expected_output_size=total_bytes_required + 1) // +1 prevents dynamic buffer grow call and hence allocation of too much space...
            //defer bytes.buffer_destroy(&buf)
            img.Data = buf.buf[:total_bytes_required]
        } else {
            // allocate memory for buffer
            data_buffer := make([]byte, total_bytes_required, allocator=allocator) or_return
            // read everything into buffer in one go directly
            os.read(fd=fd_data, data=data_buffer) or_return
            img.Data = data_buffer[:]
        }
    }
    return img, nil
}


data_deflate_zlib :: proc(data: []u8, allocator:=context.allocator) -> (deflated_data: [dynamic]u8, err: os.Error) {
    // TODO perform deflate and retrieve compressed_data_size to store in header
    // TODO there is no zlib deflate??? implement yourself?
    fmt.panicf("Compression using zlib is currently not supported as it is not implemented in Odin")
    //return 0, nil
}


image_write :: proc(img: Image, filename: string, compression: bool = false) -> (err: Error) {
    // TODO implement atomic rename trick for intermediate writing...?
    is_single_file := strings.ends_with(filename, ".mha")
    ensure(is_single_file || strings.ends_with(filename, ".mhd"))
    element_data_file : string = "LOCAL"

    // perform zlib deflate in buffer if compression is enabled
    // (do this first to retrieve the correct compressed_data_size)
    compressed_data_size : int
    compressed_data_buffer : [dynamic]u8
    if compression {
        b := data_deflate_zlib(data=img.Data, allocator=context.temp_allocator) or_return
        compressed_data_buffer = b
        compressed_data_size = len(b)
    }
    defer if compression { delete(compressed_data_buffer) }

    // if not a single file write data to element_data_file instead
    if !is_single_file {
        element_data_file = strings.concatenate({filename[:len(filename) - 3], (compression ? "zraw" : "raw")}, allocator=context.temp_allocator)
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

    os.write_string(fd, fmt.aprintfln("ObjectType = %v", objecttype_str, allocator=context.temp_allocator))
    os.write_string(fd, fmt.aprintfln("NDims = %d", img.NDims, allocator=context.temp_allocator))
    os.write_string(fd, fmt.aprintfln("BinaryData = %v", to_bool_str(img.BinaryData), allocator=context.temp_allocator))
    os.write_string(fd, fmt.aprintfln("BinaryDataByteOrderMSB = %v", to_bool_str(img.BinaryDataByteOrderMSB), allocator=context.temp_allocator))
    os.write_string(fd, fmt.aprintfln("CompressedData = %v", to_bool_str(compression), allocator=context.temp_allocator))
    if compression {
        assert(compressed_data_size > 0)
        os.write_string(fd, fmt.aprintfln("CompressedDataSize = %d", compressed_data_size, allocator=context.temp_allocator))
    }

    iterate_values_and_write :: proc(fd: os.Handle, data: []$T) {
        for e in data {
            os.write_string(fd, fmt.aprintf(" %v", e, allocator=context.temp_allocator))
        }
        os.write_string(fd, "\n")
    }

    os.write_string(fd, "TransformMatrix =")
    iterate_values_and_write(fd, img.TransformMatrix)
    os.write_string(fd, "Offset =")
    iterate_values_and_write(fd, img.Offset)

    // write metadata
    for k, v in img.MetaData {
        os.write_string(fd, k)
        os.write_string(fd, " = ")
        os.write_string(fd, v)
        os.write_string(fd, "\n")
    }

    os.write_string(fd, "ElementSpacing =")
    iterate_values_and_write(fd, img.ElementSpacing)
    os.write_string(fd, "DimSize =")
    iterate_values_and_write(fd, img.DimSize)

    os.write_string(fd, fmt.aprintfln("ElementType = %v", element_type_str, allocator=context.temp_allocator))
    os.write_string(fd, fmt.aprintfln("ElementDataFile = %v", filepath.base(element_data_file), allocator=context.temp_allocator))

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
    input_test_image_file := `.\test\test_001.mhd`
    img, err := image_read(input_test_image_file, allocator=context.allocator)
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
        testing.expect(t, img.CompressedData == compressed, fmt.aprintf("Image CompressedData should be %d", compressed, allocator=context.temp_allocator))
        if compressed {
            expected_compressed_data_size := u64(strings.ends_with(test_file_name, ".mha") ? 1702408 : 1405133)
            testing.expect(t, img.CompressedDataSize == expected_compressed_data_size, fmt.aprintf("Image CompressedDataSizeshould be equal to %d, found %d", expected_compressed_data_size, img.CompressedDataSize, allocator=context.temp_allocator))
        }

        // test meta data (for 3 test images has weird additional ITK_* tags that can be ignored)
        testing.expect(t, len(img.MetaData) == 2 || len(img.MetaData) == 5, fmt.aprintf("Found unexpected number of metadata %d != 2", len(img.MetaData), allocator=context.temp_allocator))
        testing.expect(t, ("AnatomicalOrientation" in img.MetaData) && img.MetaData["AnatomicalOrientation"] == "RAI", "MetaData key AnatomicalOrientation was found to be incorrect")
        testing.expect(t, ("CenterOfRotation" in img.MetaData) && img.MetaData["CenterOfRotation"] == "0 0 0", "MetaData key CenterOfRotation was found to be incorrect")

        expected_element_data_file := strings.concatenate({filepath.base(test_file_name[:len(test_file_name) - 3]), (compressed ? "zraw" : "raw")}, allocator=context.temp_allocator)
        expected_element_data_file = strings.ends_with(test_file_name, ".mha") ? "LOCAL" : expected_element_data_file
        testing.expect(t, img.ElementDataFile == expected_element_data_file, fmt.aprintf("Image ElementDataFile should be equal to `%s`", expected_element_data_file, allocator=context.temp_allocator))

        unexpected_values, total_voxels, total_sum := 0, 0, 0
        for data_element in img.Data {
            if data_element != 0 && data_element != 3 {
                unexpected_values += 1
            }
            total_sum += int(data_element)
            total_voxels += 1
        }
        testing.expect(t, unexpected_values == 0, "Found unexpected values in the test data")
        testing.expect(t, total_voxels == 359661568, "Found unexpected number of voxels in the test data")
        testing.expect(t, image_required_data_size(img) == total_voxels, "Found data_size larger than the total number of foxels")
        testing.expect(t, total_sum == 115079760, "Found unexpected total sum in the test data")
    }
}
