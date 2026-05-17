import os, strutils, osproc, tables, strformat, times, math, streams
import prompts

const
  ConfigFile = "config.txt"
  ProcessedDirName = ".processed"

# ImageMagick is an external image processing tool used for:
# - WEBP -> GIF conversion
# - GIF resizing
# - GIF optimization/compression
#
# Download:
# https://imagemagick.org/script/download.php#windows
#
# This project uses the portable version bundled locally
# next to the executable, so NO installation is required.
let MagickExe = getAppDir() / "ImageMagick-7.1.2-22-portable-Q16-x64" / "magick.exe"

proc loadConfig(path: string): Table[string, string] =
  # Reads config.txt into key/value pairs.
  for line in lines(path):
    let clean = line.strip()

    if clean.len == 0 or not clean.contains(":"):
      continue

    let parts = clean.split(":", maxsplit = 1)
    result[parts[0].strip()] = parts[1].strip()

proc parseMaxSizeMb(value: string): int =
  # Reads values like "20 MB" and returns 20.
  let clean = value.replace("MB", "").replace("mb", "").strip()
  parseInt(clean)

proc getProcessedDir(destPath: string): string =
  # Returns the folder used to remember processed files.
  destPath / ProcessedDirName

proc getMarkerPath(inputPath, destPath: string): string =
  # Creates a marker filename using source filename, size, and modified time.
  let info = getFileInfo(inputPath)

  let markerName =
    extractFilename(inputPath) &
    "_" & $info.size &
    "_" & $info.lastWriteTime.toUnix() &
    ".done"

  getProcessedDir(destPath) / markerName

proc isAlreadyProcessed(inputPath, destPath: string): bool =
  # Checks whether this exact file version was already processed.
  fileExists(getMarkerPath(inputPath, destPath))

proc markAsProcessed(inputPath, destPath: string) =
  # Creates a marker file after successful processing.
  let processedDir = getProcessedDir(destPath)

  createDir(processedDir)

  let markerPath = getMarkerPath(inputPath, destPath)
  writeFile(markerPath, "processed")

proc estimateScale(currentSize, maxSizeBytes: int): int =
  # Estimates a good starting resize percentage from the size ratio.
  if currentSize <= 0:
    return 90

  let ratio = maxSizeBytes.float / currentSize.float

  var scale = int(sqrt(ratio) * 100)

  if scale > 95:
    scale = 95
  elif scale < 10:
    scale = 10

  scale

proc getRealFormat(filePath: string): string =
  # Uses ImageMagick identify to detect the real file format.
  if not fileExists(MagickExe):
    echo "Warning: ImageMagick not found: ", MagickExe
    return ""

  let args = @[
    "identify",
    "-format",
    "%m",
    filePath
  ]

  let process = startProcess(
    MagickExe,
    args = args,
    options = {}
  )

  let output = process.outputStream.readAll().toLowerAscii()
  let code = process.waitForExit()
  process.close()

  if code != 0:
    return ""

  if output.contains("webp"):
    return "webp"

  if output.contains("gif"):
    return "gif"

  ""

proc runMagick(
  inputPath,
  outputPath: string,
  scale: int,
  optimize: bool = true
): bool =
  # Runs local ImageMagick to convert/resize GIFs.
  if not fileExists(MagickExe):
    echo "Warning: ImageMagick not found: ", MagickExe
    return false

  var args = @[
    inputPath,
    "-coalesce",
    "-resize", $scale & "%"
  ]

  if optimize:
    args.add("-layers")
    args.add("Optimize")

  args.add(outputPath)

  let code = runWithDots(
    MagickExe,
    args,
    "  ImageMagick processing"
  )

  if code == 0:
    true
  else:
    echo "Warning: ImageMagick failed."
    false

proc resizeUntilUnderLimit(
  inputPath,
  outputPath: string,
  currentSize,
  maxSizeMb,
  maxSizeBytes: int
): bool =
  # Starts near the estimated scale, then shrinks more only if needed.
  var scale = estimateScale(currentSize, maxSizeBytes)

  echo "  Estimated starting scale: ", scale, "%"

  while scale >= 10:
    echo "  Trying scale: ", scale, "%"

    let success = runMagick(
      inputPath,
      outputPath,
      scale,
      optimize = true
    )

    if success and fileExists(outputPath):
      let outputSize = getFileSize(outputPath)

      if outputSize <= maxSizeBytes:
        echo fmt"Saved resized: {outputPath} ({sizeMb(outputPath):.2f} MB)"
        return true
      else:
        echo fmt"  Still too large: {sizeMb(outputPath):.2f} MB"

    scale -= 5

  echo fmt"Warning: Could not resize under {maxSizeMb} MB: {inputPath}"
  false

proc convertOrCopyFile(
  inputPath,
  destPath: string,
  maxSizeMb,
  maxSizeBytes: int
): bool =
  # Copies small GIFs, converts WEBPs, and resizes oversized files.
  let info = splitFile(inputPath)

  let realFormat = getRealFormat(inputPath)

  let normalOutput =
    destPath / (info.name & ".gif")

  let resizedOutput =
    destPath / (info.name & "_resized.gif")

  if realFormat == "gif":
    let inputSize = getFileSize(inputPath)

    if inputSize <= maxSizeBytes:
      copyFile(inputPath, normalOutput)

      echo fmt"Copied: {normalOutput} ({sizeMb(normalOutput):.2f} MB)"
      return true
    else:
      echo fmt"GIF is over {maxSizeMb} MB. Resizing..."

      return resizeUntilUnderLimit(
        inputPath,
        resizedOutput,
        inputSize,
        maxSizeMb,
        maxSizeBytes
      )

  elif realFormat == "webp":
    echo "Converting WEBP to GIF first..."

    let success = runMagick(
      inputPath,
      normalOutput,
      100,
      optimize = false
    )

    if not success or not fileExists(normalOutput):
      echo "Warning: Failed to convert: ", inputPath
      return false

    let convertedSize = getFileSize(normalOutput)

    if convertedSize <= maxSizeBytes:
      echo fmt"Converted: {normalOutput} ({sizeMb(normalOutput):.2f} MB)"
      return true
    else:
      echo fmt"Converted GIF is too large: {sizeMb(normalOutput):.2f} MB"

      echo "Removing oversized GIF and creating resized version..."

      removeFile(normalOutput)

      return resizeUntilUnderLimit(
        inputPath,
        resizedOutput,
        convertedSize,
        maxSizeMb,
        maxSizeBytes
      )

  else:
    echo "Skipping unsupported or unknown format: ", inputPath

  false

proc processFolder(
  srcPath,
  destPath: string,
  maxSizeMb,
  maxSizeBytes: int
) =
  # Validates folders and processes every supported file.
  if not dirExists(srcPath):
    echo "Source folder not found. Creating: ", srcPath

    createDir(srcPath)

    echo "Put .gif or .webp files into the folder and run again."
    return

  createDir(destPath)
  createDir(getProcessedDir(destPath))

  var found = false

  let totalStart = epochTime()

  for file in walkFiles(srcPath / "*"):
    let realFormat = getRealFormat(file)

    if realFormat == "gif" or realFormat == "webp":
      found = true

      if isAlreadyProcessed(file, destPath):
        echo "Skipping already processed: ", extractFilename(file)
        continue

      echo "Processing: ", extractFilename(file)

      let fileStart = epochTime()

      let success = convertOrCopyFile(
        file,
        destPath,
        maxSizeMb,
        maxSizeBytes
      )

      if success:
        markAsProcessed(file, destPath)

      let fileElapsed = epochTime() - fileStart

      echo fmt"Finished in {fileElapsed:.2f} seconds"
      echo ""

  let totalElapsed = epochTime() - totalStart

  if not found:
    echo "Warning: No supported GIF/WEBP files found in: ", srcPath
  else:
    echo fmt"Total processing time: {totalElapsed:.2f} seconds"
    echo ""

proc main() =
  # Program entry point.
  let config = loadConfig(ConfigFile)

  let maxSizeMb = parseMaxSizeMb(config["max_size"])
  let maxSizeBytes = maxSizeMb * 1024 * 1024

  echo "Press ENTER to use config.txt defaults."
  echo ""

  let srcPath =
    askPath("Source folder", config["src_path"])

  let destPath =
    askPath("Destination folder", config["dest_path"])

  echo ""
  echo "Using source: ", srcPath
  echo "Using destination: ", destPath
  echo "Max GIF size: ", maxSizeMb, " MB"
  echo ""

  listFiles(srcPath)

  processFolder(
    srcPath,
    destPath,
    maxSizeMb,
    maxSizeBytes
  )

  listFiles(destPath)

  waitBeforeExit()

when isMainModule:
  main()
