package tests

import "core:os"
import "core:fmt"
import "core:testing"
import "core:strings"
import "core:slice"
import "core:path/filepath"

import "../metaio"


TEST_RES_DIR :: `.\res`

TEST_COMPRESSED_MHD_FILE :: TEST_RES_DIR + `\test_001.mhd`
TEST_COMPRESSED_MHA_FILE :: TEST_RES_DIR + `\test_001.mha`
TEST_UNCOMPRESSED_MHD_FILE :: TEST_RES_DIR + `\test_001_uncompressed.mhd`
TEST_UNCOMPRESSED_MHA_FILE :: TEST_RES_DIR + `\test_001_uncompressed.mha`

@(test)
test_image_read_compressed_mhd :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_COMPRESSED_MHD_FILE, compressed=true)
}

@(test)
test_image_read_compressed_mha :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_COMPRESSED_MHA_FILE, compressed=true)
}

@(test)
test_image_read_uncompressed_mhd :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_UNCOMPRESSED_MHD_FILE, compressed=false)
}

@(test)
test_image_read_uncompressed_mha :: proc(t: ^testing.T) {
    test_image_read_expected_values(t=t, test_file_name=TEST_UNCOMPRESSED_MHA_FILE, compressed=false)
}

@(test)
test_image_write_uncompressed_mha :: proc(t: ^testing.T) {
    input_test_image_file := TEST_COMPRESSED_MHD_FILE
    output_test_image_file := TEST_COMPRESSED_MHD_FILE + `write_output.mha`
    img, err := metaio.image_read(input_test_image_file, allocator=context.allocator)
    defer metaio.image_destroy(img, allocator=context.allocator)
    free_all(context.temp_allocator)
    write_err := metaio.image_write(img, output_test_image_file, false)
    defer if os.exists(output_test_image_file) { os.unlink(output_test_image_file) }
    testing.expect(t, os.exists(input_test_image_file), fmt.aprintf("Input test file does not exist: %s", input_test_image_file, allocator=context.temp_allocator))
    testing.expect(t, os.exists(output_test_image_file), fmt.aprintf("Output test file does not exist: %s", output_test_image_file, allocator=context.temp_allocator))
    test_image_read_expected_values(t=t, test_file_name=output_test_image_file, compressed=false)
}

@(test)
test_image_write_uncompressed_mhd :: proc(t: ^testing.T) {
    input_test_image_file := TEST_COMPRESSED_MHD_FILE
    output_test_image_file := TEST_COMPRESSED_MHD_FILE + `write_output.mhd`
    output_test_image_data_file := TEST_COMPRESSED_MHD_FILE + `write_output.raw`
    img, err := metaio.image_read(input_test_image_file, allocator=context.allocator)
    defer metaio.image_destroy(img, allocator=context.allocator)
    free_all(context.temp_allocator)
    write_err := metaio.image_write(img, output_test_image_file, false)
    defer if os.exists(output_test_image_file) { os.unlink(output_test_image_file) }
    defer if os.exists(output_test_image_data_file) { os.unlink(output_test_image_data_file) }
    testing.expect(t, os.exists(input_test_image_file), fmt.aprintf("Input test file does not exist: %s", input_test_image_file, allocator=context.temp_allocator))
    testing.expect(t, os.exists(output_test_image_file), fmt.aprintf("Output test file does not exist: %s", output_test_image_file, allocator=context.temp_allocator))
    testing.expect(t, os.exists(output_test_image_data_file), fmt.aprintf("Output test data file does not exist: %s", output_test_image_data_file, allocator=context.temp_allocator))
    test_image_read_expected_values(t=t, test_file_name=output_test_image_file, compressed=false)
}

@(test)
test_image_write_compressed_mha :: proc(t: ^testing.T) {
    input_test_image_file := TEST_COMPRESSED_MHD_FILE
    output_test_image_file := TEST_COMPRESSED_MHD_FILE + `write_output_compressed.mha`
    img, err := metaio.image_read(input_test_image_file, allocator=context.allocator)
    testing.expect(t, err == nil, fmt.aprintf("\nFOUND READ ERROR: %v", err, allocator=context.temp_allocator))
    if err != nil {
        return
    }
    defer metaio.image_destroy(img, allocator=context.allocator)
    free_all(context.temp_allocator)
    write_err := metaio.image_write(img, output_test_image_file, true)
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
    input_test_image_file := TEST_COMPRESSED_MHD_FILE
    output_test_image_file := TEST_COMPRESSED_MHD_FILE + `write_output_compressed.mhd`
    output_test_image_data_file := TEST_COMPRESSED_MHD_FILE + `write_output_compressed.zraw`
    img, err := metaio.image_read(input_test_image_file, allocator=context.allocator)
    testing.expect(t, err == nil, fmt.aprintf("\nFOUND READ ERROR: %v", err, allocator=context.temp_allocator))
    if err != nil {
        return
    }
    defer metaio.image_destroy(img, allocator=context.allocator)
    free_all(context.temp_allocator)
    write_err := metaio.image_write(img, output_test_image_file, true)
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
    img, err := metaio.image_read(test_file_name, allocator=context.allocator)
    defer metaio.image_destroy(img, allocator=context.allocator)
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
    testing.expect(t, metaio.image_required_data_size(img) == total_voxels, fmt.aprintf("Found data_size (%d) != than the total number of voxels (%d)", metaio.image_required_data_size(img), total_voxels, allocator=context.temp_allocator))
    testing.expect(t, total_sum == 115079760, "Found unexpected total sum in the test data")
}
