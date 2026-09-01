#define STB_DXT_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#include <string.h>
#include "stb_dxt.h"

// Download from: https://github.com/nothings/stb
#include "stb_image.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#ifdef _OPENMP
#include <omp.h>
#endif

// DDS header structures
#pragma pack(push, 1)
typedef struct {
    uint32_t dwMagic;        // "DDS " = 0x20534444
    uint32_t dwSize;         // 124
    uint32_t dwFlags;        // flags
    uint32_t dwHeight;       // height
    uint32_t dwWidth;        // width
    uint32_t dwPitchOrLinearSize; // pitch or linear size
    uint32_t dwDepth;        // depth
    uint32_t dwMipMapCount;  // mipmap count
    uint32_t dwReserved1[11]; // reserved
    
    // DDS_PIXELFORMAT (32 bytes)
    struct {
        uint32_t dwSize;        // 32
        uint32_t dwFlags;       // flags
        uint32_t dwFourCC;      // fourcc
        uint32_t dwRGBBitCount; // rgb bit count
        uint32_t dwRBitMask;    // r bit mask
        uint32_t dwGBitMask;    // g bit mask
        uint32_t dwBBitMask;    // b bit mask
        uint32_t dwABitMask;    // a bit mask
    } ddspf;
    
    uint32_t dwCaps;         // caps
    uint32_t dwCaps2;        // caps2
    uint32_t dwCaps3;        // caps3
    uint32_t dwCaps4;        // caps4
    uint32_t dwReserved2;    // reserved
} DDS_HEADER;
#pragma pack(pop)

// DDS constants
#define DDSD_CAPS         0x1
#define DDSD_HEIGHT       0x2
#define DDSD_WIDTH        0x4
#define DDSD_PIXELFORMAT  0x1000
#define DDSD_LINEARSIZE   0x80000

#define DDPF_FOURCC       0x4

#define DDSCAPS_TEXTURE   0x1000

// BC3/DXT5 constants
#define BC3_BLOCK_SIZE 16
#define BLOCK_DIM 4

uint32_t make_fourcc(char a, char b, char c, char d) {
    return (uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) | ((uint32_t)(d) << 24);
}

int compress_to_bc3(const char* input_path, const char* output_path) {
    printf("Loading image: %s\n", input_path);
    
    int width, height, channels;
    unsigned char* image_data = stbi_load(input_path, &width, &height, &channels, 4); // Force RGBA
    if (!image_data) {
        printf("Error: Failed to load image '%s'\n", input_path);
        return 1;
    }
    
    printf("Image loaded: %dx%d, %d channels (converted to RGBA)\n", width, height, channels);
    
    // Calculate block dimensions
    int blocks_x = (width + BLOCK_DIM - 1) / BLOCK_DIM;
    int blocks_y = (height + BLOCK_DIM - 1) / BLOCK_DIM;
    int total_blocks = blocks_x * blocks_y;
    
    printf("Block grid: %dx%d = %d blocks\n", blocks_x, blocks_y, total_blocks);
    
    // Calculate expected sizes
    size_t original_size = width * height * 4; // Always RGBA after stbi_load conversion
    size_t compressed_size = total_blocks * BC3_BLOCK_SIZE;
    
    printf("Expected sizes:\n");
    printf("  Original: %zu bytes (RGBA)\n", original_size);
    printf("  Compressed: %zu bytes\n", compressed_size);
    printf("  Ratio: %.2fx compression\n", (float)original_size / (float)compressed_size);
    
    // Allocate compressed data
    unsigned char* compressed_data = malloc(compressed_size);
    if (!compressed_data) {
        printf("Error: Failed to allocate %zu bytes for compressed data\n", compressed_size);
        stbi_image_free(image_data);
        return 1;
    }
    
#ifdef _OPENMP
    printf("Compressing blocks to BC3/DXT5 (parallel, %d threads)...\n", omp_get_max_threads());
#else
    printf("Compressing blocks to BC3/DXT5...\n");
#endif

    // Compress each 4x4 block. Every block only reads from image_data and
    // writes its own 16-byte slice of compressed_data, so rows are fully
    // independent and safe to parallelize (output is identical regardless
    // of how many threads process it, just faster on large atlases).
    #pragma omp parallel for schedule(dynamic) if(blocks_y > 4)
    for (int by = 0; by < blocks_y; by++) {
        for (int bx = 0; bx < blocks_x; bx++) {
            // BC3 expects RGBA data (4 bytes per pixel, 64 bytes per 4x4 block uncompressed)
            unsigned char block_rgba[BLOCK_DIM * BLOCK_DIM * 4];

            // Extract 4x4 block
            for (int py = 0; py < BLOCK_DIM; py++) {
                for (int px = 0; px < BLOCK_DIM; px++) {
                    int src_x = bx * BLOCK_DIM + px;
                    int src_y = by * BLOCK_DIM + py;

                    // Clamp to image bounds
                    if (src_x >= width) src_x = width - 1;
                    if (src_y >= height) src_y = height - 1;

                    int src_idx = (src_y * width + src_x) * 4; // RGBA
                    int dst_idx = (py * BLOCK_DIM + px) * 4;

                    // Copy RGBA channels
                    block_rgba[dst_idx + 0] = image_data[src_idx + 0]; // R
                    block_rgba[dst_idx + 1] = image_data[src_idx + 1]; // G
                    block_rgba[dst_idx + 2] = image_data[src_idx + 2]; // B
                    block_rgba[dst_idx + 3] = image_data[src_idx + 3]; // A
                }
            }

            // Compress this block to BC3/DXT5
            int block_idx = by * blocks_x + bx;
            stb_compress_dxt_block(compressed_data + block_idx * BC3_BLOCK_SIZE,
                                   block_rgba, 1, STB_DXT_DITHER | STB_DXT_HIGHQUAL);
            // Note: STB uses mode=1 for DXT5/BC3 (RGBA with alpha)
        }

#ifndef _OPENMP
        if ((by + 1) % 10 == 0 || by == blocks_y - 1) {
            printf("  Processed %d/%d block rows\n", by + 1, blocks_y);
        }
#endif
    }

    printf("Writing DDS file: %s\n", output_path);
    
    // Write DDS file
    FILE* output_file = fopen(output_path, "wb");
    if (!output_file) {
        printf("Error: Failed to create output file '%s'\n", output_path);
        free(compressed_data);
        stbi_image_free(image_data);
        return 1;
    }
    
    // Write DDS header
    DDS_HEADER header = {0};
    header.dwMagic = make_fourcc('D', 'D', 'S', ' ');
    header.dwSize = 124;
    header.dwFlags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_LINEARSIZE;
    header.dwHeight = height;
    header.dwWidth = width;
    header.dwPitchOrLinearSize = compressed_size; // Total compressed size
    header.dwDepth = 0;
    header.dwMipMapCount = 0;
    
    // BC3/DXT5 pixel format
    header.ddspf.dwSize = 32;
    header.ddspf.dwFlags = DDPF_FOURCC;
    header.ddspf.dwFourCC = make_fourcc('D', 'X', 'T', '5'); // DXT5 format (BC3)
    header.ddspf.dwRGBBitCount = 0;
    header.ddspf.dwRBitMask = 0;
    header.ddspf.dwGBitMask = 0;
    header.ddspf.dwBBitMask = 0;
    header.ddspf.dwABitMask = 0;
    
    header.dwCaps = DDSCAPS_TEXTURE;
    header.dwCaps2 = 0;
    header.dwCaps3 = 0;
    header.dwCaps4 = 0;
    header.dwReserved2 = 0;
    
    // Write header
    if (fwrite(&header, sizeof(header), 1, output_file) != 1) {
        printf("Error: Failed to write DDS header\n");
        fclose(output_file);
        free(compressed_data);
        stbi_image_free(image_data);
        return 1;
    }
    
    // Write compressed data
    if (fwrite(compressed_data, 1, compressed_size, output_file) != compressed_size) {
        printf("Error: Failed to write compressed data\n");
        fclose(output_file);
        free(compressed_data);
        stbi_image_free(image_data);
        return 1;
    }
    
    fclose(output_file);
    
    // Verify file size
    FILE* verify = fopen(output_path, "rb");
    if (verify) {
        fseek(verify, 0, SEEK_END);
        long actual_file_size = ftell(verify);
        fclose(verify);
        
        size_t expected_file_size = sizeof(DDS_HEADER) + compressed_size;
        
        printf("\nFile size verification:\n");
        printf("  Expected: %zu bytes (header: %zu + data: %zu)\n", 
               expected_file_size, sizeof(DDS_HEADER), compressed_size);
        printf("  Actual: %ld bytes\n", actual_file_size);
        
        if (actual_file_size != expected_file_size) {
            printf("  WARNING: File size mismatch!\n");
        } else {
            printf("  File size correct!\n");
        }
    }
    
    // Final stats
    printf("\nCompression Results:\n");
    printf("  Input: %s (%dx%d, %d channels)\n", input_path, width, height, channels);
    printf("  Output: %s (BC3/DXT5 RGBA)\n", output_path);
    printf("  Original size: %zu bytes\n", original_size);
    printf("  Compressed size: %zu bytes\n", compressed_size);
    printf("  Compression ratio: %.2fx\n", (float)original_size / (float)compressed_size);
    printf("  Space saved: %.1f%%\n", 100.0f * (1.0f - (float)compressed_size / (float)original_size));
    
    // Cleanup
    free(compressed_data);
    stbi_image_free(image_data);
    
    return 0;
}

int main(int argc, char* argv[]) {
    if (argc != 3) {
        printf("BC3/DXT5 Texture Compressor\n");
        printf("Usage: %s <input.png> <output.dds>\n", argv[0]);
        printf("\n");
        printf("Compresses images to BC3/DXT5 format for GPU texture compression.\n");
        printf("BC3/DXT5 preserves full RGBA channels with 4:1 compression ratio.\n");
        printf("Perfect for sprites with alpha cutouts. Excellent WebGL support.\n");
        return 1;
    }
    
    return compress_to_bc3(argv[1], argv[2]);
}