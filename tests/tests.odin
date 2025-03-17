package tests

import "core:os"
import "core:io"
import "core:fmt"
import "core:bytes"
import "core:testing"
import "core:strings"
import "core:slice"
import "core:path/filepath"

import "../metaimage"


TEST_RES_DIR :: `.\tests\res`

TEST_COMPRESSED_MHD_FILE :: TEST_RES_DIR + `\test_001.mhd`
TEST_COMPRESSED_MHA_FILE :: TEST_RES_DIR + `\test_001.mha`
TEST_UNCOMPRESSED_MHD_FILE :: TEST_RES_DIR + `\test_001_uncompressed.mhd`
TEST_UNCOMPRESSED_MHA_FILE :: TEST_RES_DIR + `\test_001_uncompressed.mha`

TEST_TINY_COMPRESSED_MHA_FILE :: TEST_RES_DIR + `\test_002.mha`
TEST_TINY_UNCOMPRESSED_MHA_FILE :: TEST_RES_DIR + `\test_002_uncompressed.mha`

TEST_UNCOMPRESSED_DATA :: []u8{0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 3, 1, 0, 0, 0, 0, 0}
TEST_COMPRESSED_DATA :: []u8{120, 156, 99, 96, 128, 2, 22, 38, 6, 56, 96, 6, 97, 70, 48, 19, 0, 0, 228, 0, 14}
TEST_COMPRESSED_DATA_FAST :: []u8{120, 1, 99, 128, 1, 22, 38, 6, 56, 96, 102, 96, 96, 96, 102, 100, 0, 1, 0, 0, 228, 0, 14}


@(test)
test_image_read_uncompressed_mhd :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_UNCOMPRESSED_MHD_FILE, compressed=false)
}

@(test)
test_image_read_uncompressed_mha :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_UNCOMPRESSED_MHA_FILE, compressed=false)
}

@(test)
test_image_read_compressed_mhd :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_COMPRESSED_MHD_FILE, compressed=true)
}

@(test)
test_image_read_compressed_mha :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_COMPRESSED_MHA_FILE, compressed=true)
}

@(test)
test_image_write_uncompressed_mha :: proc(t: ^testing.T) {
    test_image_write(t=t, test_file_name=TEST_COMPRESSED_MHD_FILE, is_single_file=true, compressed=false)
}

@(test)
test_image_write_uncompressed_mhd :: proc(t: ^testing.T) {
    test_image_write(t=t, test_file_name=TEST_COMPRESSED_MHD_FILE, is_single_file=false, compressed=false)
}

@(test)
test_image_write_compressed_mha :: proc(t: ^testing.T) {
    test_image_write(t=t, test_file_name=TEST_COMPRESSED_MHD_FILE, is_single_file=true, compressed=true)
}

@(test)
test_image_write_compressed_mhd :: proc(t: ^testing.T) {
    test_image_write(t=t, test_file_name=TEST_COMPRESSED_MHD_FILE, is_single_file=false, compressed=true)
}

@(test)
test_image_zlib_decompress :: proc(t: ^testing.T) {
    uncompressed_data, err := metaimage.zlib_inflate_data(data=TEST_COMPRESSED_DATA, expected_output_size=len(TEST_UNCOMPRESSED_DATA), allocator=context.temp_allocator)
    testing.expect(t, err == nil, fmt.aprintf("Decompression operation returned unexpected error: %v", err, allocator=context.temp_allocator))
    if err == nil {
        testing.expect(t, slice.equal(uncompressed_data, TEST_UNCOMPRESSED_DATA), "Decompressed data does not match expected output")
    }
}

@(test)
test_image_zlib_compress :: proc(t: ^testing.T) {
    compressed_data, err := metaimage.zlib_deflate_data(data=TEST_UNCOMPRESSED_DATA, options=metaimage.DEFAULT_COMPRESSION_OPTIONS, allocator=context.temp_allocator)
    testing.expect(t, err == nil, fmt.aprintf("Compression operation returned unexpected error: %v", err, allocator=context.temp_allocator))
    if err == nil {
        testing.expect(t, slice.equal(compressed_data, TEST_COMPRESSED_DATA), "Compressed data does not match expected output")
    }
}

@(test)
test_image_zlib_decompress_fast :: proc(t: ^testing.T) {
    uncompressed_data, err := metaimage.zlib_inflate_data(data=TEST_COMPRESSED_DATA_FAST, expected_output_size=len(TEST_UNCOMPRESSED_DATA), allocator=context.temp_allocator)
    testing.expect(t, err == nil, fmt.aprintf("Decompression operation returned unexpected error: %v", err, allocator=context.temp_allocator))
    if err == nil {
        testing.expect(t, slice.equal(uncompressed_data, TEST_UNCOMPRESSED_DATA), "Decompressed data does not match expected output")
    }
}

@(test)
test_image_zlib_compress_fast :: proc(t: ^testing.T) {
    compressed_data, err := metaimage.zlib_deflate_data(data=TEST_UNCOMPRESSED_DATA, options=metaimage.FAST_COMPRESSION_OPTIONS, allocator=context.temp_allocator)
    testing.expect(t, err == nil, fmt.aprintf("Compression operation returned unexpected error: %v", err, allocator=context.temp_allocator))
    if err == nil {
        testing.expect(t, slice.equal(compressed_data, TEST_COMPRESSED_DATA_FAST), "Compressed data does not match expected output")
    }
}

@(test)
test_image_stream_read_write :: proc(t: ^testing.T) {
    input_img, err := metaimage.read(TEST_TINY_COMPRESSED_MHA_FILE, allocator=context.allocator)
    testing.expect(t, err == nil, fmt.aprintf("\nFOUND READ ERROR: %v", err, allocator=context.temp_allocator))
    if err != nil {
        return
    }
    defer metaimage.destroy(input_img, allocator=context.allocator)

    buffer : bytes.Buffer
    bytes.buffer_init_allocator(b=&buffer, len=0, cap=1200, allocator=context.allocator)
    defer bytes.buffer_destroy(b=&buffer)
    bytes_buffer := bytes.buffer_to_stream(b=&buffer)
    defer io.close(bytes_buffer)

    compressed_data := []u8{}
    stream_write_error := metaimage.write_to_stream(img=input_img, writer_stream=bytes_buffer, element_data_file="LOCAL", compression=true, compressed_data=compressed_data, allocator=context.temp_allocator)
    testing.expect(t, stream_write_error == nil, fmt.aprintf("\nFOUND WRITE ERROR: %v", stream_write_error, allocator=context.temp_allocator))
    if stream_write_error != nil {
        return
    }

    output_img, stream_read_error := metaimage.read_from_stream(reader_stream=bytes_buffer, data_dir=".", allocator=context.allocator)
    testing.expect(t, err == nil, fmt.aprintf("\nFound read from stream error: %v", stream_read_error, allocator=context.temp_allocator))
    if stream_read_error != nil {
        return
    }
    defer metaimage.destroy(output_img, allocator=context.allocator)
    input_img_repr := fmt.aprintf("%v", input_img, allocator=context.temp_allocator)
    output_img_repr := fmt.aprintf("%v", output_img, allocator=context.temp_allocator)
    testing.expect(
        t,
        metaimage.equal(input_img, output_img),
        fmt.aprintf(
            "Image data are expected to be the same, found:\nA:%v\n\nB:%v",
            input_img_repr,
            output_img_repr,
            allocator=context.temp_allocator
        )
    )
}

test_image_write :: proc(t: ^testing.T, test_file_name: string, is_single_file: bool, compressed: bool, loc:=#caller_location) {
    input_test_image_file := test_file_name
    // Weird unique output test file naming in order to prevent threaded file write collisions.
    output_test_image_file := strings.concatenate({test_file_name[:len(test_file_name)-4], `_write_output_`, (compressed ? `compressed` : `uncompressed`), (is_single_file ? `_mha.mha` : `_mhd.mhd`)}, allocator=context.allocator)
    output_test_image_data_file := strings.concatenate({output_test_image_file[:len(output_test_image_file) - 4], (compressed ? `.zraw` : `.raw`)}, allocator=context.allocator)
    defer delete(output_test_image_file, allocator=context.allocator)
    defer delete(output_test_image_data_file, allocator=context.allocator)
    img, err := metaimage.read(input_test_image_file, allocator=context.allocator)
    testing.expect(t, err == nil, fmt.aprintf("\nFOUND READ ERROR: %v", err, allocator=context.temp_allocator))
    if err != nil {
        return
    }
    defer metaimage.destroy(img, allocator=context.allocator)
    write_err := metaimage.write(img, output_test_image_file, compressed)
    testing.expect(t, write_err == nil, fmt.aprintf("\nFOUND WRITE ERROR: %v", write_err, allocator=context.temp_allocator))
    if write_err != nil {
        return
    }
    defer if os.exists(output_test_image_file) { os.unlink(output_test_image_file) }
    defer if os.exists(output_test_image_data_file) { os.unlink(output_test_image_data_file) }
    testing.expect(t, os.exists(input_test_image_file), fmt.aprintf("Input test file does not exist: %s", input_test_image_file, allocator=context.temp_allocator))
    testing.expect(t, os.exists(output_test_image_file), fmt.aprintf("Output test file does not exist: %s", output_test_image_file, allocator=context.temp_allocator))
    if !is_single_file {
        testing.expect(t, os.exists(output_test_image_data_file), fmt.aprintf("Output test data file does not exist: %s", output_test_image_data_file, allocator=context.temp_allocator))
    }
    test_image_read_expected_values(t=t, test_file_name=output_test_image_file, compressed=compressed)
}

test_image_read_expected_values :: proc(t: ^testing.T, test_file_name: string, compressed: bool) {
    img, err := metaimage.read(test_file_name, allocator=context.allocator)
    defer metaimage.destroy(img, allocator=context.allocator)
    free_all(context.temp_allocator)

    EXPECTED_NDIMS            :: 3
    EXPECTED_DIM_SIZES        :: []u16{32, 32, 18}
    EXPECTED_ELEMENT_SPACING  :: []f64{13.75, 13.75, 19.861110687255859}
    EXPECTED_OFFSET           :: []f64{-192.85468750000001, -213.5546875, -385.81944444444446}
    EXPECTED_TRANSFORM_MATRIX :: []f64{1, 0, 0, 0, 1, 0, 0, 0, 1}
    EXPECTED_COMPRESSION_SIZE :: 648
    EXPECTED_TOTAL_VOXELS     :: 18432
    EXPECTED_DATA_CHECKSUM    :: 5460
    EXPECTED_UNIQUE_DATA_ELEM :: []u8{0, 1, 2, 3, 4, 5}

    testing.expect(t, os.exists(test_file_name), fmt.aprintf("Test file does not exist: %s", test_file_name, allocator=context.temp_allocator))
    if !os.exists(test_file_name) {
        return
    }
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
        testing.expect(t, img.CompressedDataSize == EXPECTED_COMPRESSION_SIZE, fmt.aprintf("Image CompressedDataSize should be %d, found %d", EXPECTED_COMPRESSION_SIZE, img.CompressedDataSize, allocator=context.temp_allocator))
    }

    // test meta data (for 3 test images has weird additional ITK_* tags that can be ignored)
    testing.expect(t, len(img.MetaData) == 2, fmt.aprintf("Found unexpected number of metadata %d != 2", len(img.MetaData), allocator=context.temp_allocator))
    testing.expect(t, ("AnatomicalOrientation" in img.MetaData) && img.MetaData["AnatomicalOrientation"] == "RAI", "MetaData key AnatomicalOrientation was found to be incorrect")
    testing.expect(t, ("CenterOfRotation" in img.MetaData) && img.MetaData["CenterOfRotation"] == "0 0 0", "MetaData key CenterOfRotation was found to be incorrect")

    expected_element_data_file := strings.concatenate({filepath.base(test_file_name[:len(test_file_name) - 3]), (compressed ? "zraw" : "raw")}, allocator=context.temp_allocator)
    expected_element_data_file = strings.ends_with(test_file_name, ".mha") ? "LOCAL" : expected_element_data_file
    testing.expect(t, img.ElementDataFile == expected_element_data_file, fmt.aprintf("Image ElementDataFile should be equal to `%s`", expected_element_data_file, allocator=context.temp_allocator))

    unexpected_values, total_voxels, total_sum : uint = 0, 0, 0
    for data_element in img.Data {
        if !slice.contains(EXPECTED_UNIQUE_DATA_ELEM, data_element) {
            unexpected_values += 1
        }
        total_sum += uint(data_element)
        total_voxels += 1
    }
    testing.expect(t, unexpected_values == 0, "Found unexpected values in the test data")
    testing.expect(t, total_voxels == EXPECTED_TOTAL_VOXELS, "Found unexpected number of voxels in the test data")
    testing.expect(t, metaimage.required_data_size(img) == total_voxels, fmt.aprintf("Found data_size (%d) != than the total number of voxels (%d)", metaimage.required_data_size(img), total_voxels, allocator=context.temp_allocator))
    testing.expect(t, total_sum == EXPECTED_DATA_CHECKSUM, "Found unexpected total sum in the test data")
}
