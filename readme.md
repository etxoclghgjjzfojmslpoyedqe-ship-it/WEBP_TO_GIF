# WEBP to GIF Converter

A simple portable Windows tool for converting `.webp` files to `.gif` and keeping GIF files under a size limit, such as `20 MB`.

This is useful for websites that only allow GIF uploads up to a certain file size.

## What This Tool Does

- Converts `.webp` files into `.gif`
- Copies `.gif` files that are already small enough
- Resizes oversized files automatically
- Saves converted files into the destination folder
- Uses `config.txt` for simple settings

## Folder Layout

Keep the files like this:

```txt
WEBP_TO_GIF/
├── ImageMagick-7.1.2-22-portable-Q16-x64/
├── img_source/
├── img_converted/
├── LICENSES/
├── config.txt
└── main.exe
```

## How to Use

### 1. Put your files into `img_source`

Put your `.webp` or `.gif` files here:

```txt
img_source/
```

### 2. Run `main.exe`

Double-click:

```txt
main.exe
```

### 3. Press Enter twice

When this appears:

```txt
Source folder [ENTER = img_source]:
Destination folder [ENTER = img_converted]:
```

Just press:

```txt
Enter
Enter
```

This uses the default folders from `config.txt`.

### 4. Check `img_converted`

The finished GIF files will appear here:

```txt
img_converted/
```

## Config File

Default `config.txt`:

```txt
src_path: img_source
dest_path: img_converted
max_size: 20 MB
```

You can change the size limit:

```txt
max_size: 15 MB
```

Only `MB` is supported.

## Output Names

If a file does not need resizing:

```txt
example.gif
```

If a file needed resizing:

```txt
example_resized.gif
```

## Notes

- No installation is required.
- ImageMagick is already bundled with this tool.
- Do not delete the ImageMagick folder.
- Keep `config.txt` next to `main.exe`.

## Source Code

The Nim source files are available separately in the repository source code.

## Credits

This tool uses ImageMagick for image conversion and resizing.

ImageMagick:
https://imagemagick.org/

Built in Nim with assistance from ChatGPT.