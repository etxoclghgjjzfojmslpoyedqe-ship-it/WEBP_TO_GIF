import os, strutils, strformat, osproc

proc sizeMb*(path: string): float =
  # Converts file size from bytes to MB.
  getFileSize(path).float / 1024 / 1024

proc askPath*(prompt, defaultPath: string): string =
  # Asks for a path, or returns the default if ENTER is pressed.
  stdout.write(prompt & " [ENTER = " & defaultPath & "]: ")
  let input = stdin.readLine().strip()

  if input.len == 0:
    defaultPath
  else:
    input

proc printFileInfo(path: string) =
  # Prints one file as: filename (size MB).
  echo fmt"{extractFilename(path)} ({sizeMb(path):.2f} MB)"

proc listFiles*(folderPath: string) =
  # Lists GIF/WEBP files in one-line format.
  echo "================================="
  echo "Files in: ", folderPath
  echo "================================="

  var found = false

  if dirExists(folderPath):
    for file in walkFiles(folderPath / "*"):
      let ext = splitFile(file).ext.toLowerAscii()

      if ext == ".gif" or ext == ".webp":
        found = true
        printFileInfo(file)

  if not found:
    echo "No .gif or .webp files found."

  echo "================================="
  echo ""

proc runWithDots*(program: string, args: openArray[string], message: string): int =
  # Runs a program while showing a simple processing animation.
  let dots = [".", "..", "..."]
  var i = 0

  let process = startProcess(
    program,
    args = args,
    options = {}
  )

  while process.running():
    stdout.write("\r" & message & dots[i mod dots.len] & "   ")
    stdout.flushFile()
    sleep(300)
    i += 1

  result = process.waitForExit()
  process.close()

  stdout.write("\r" & message & " done   \n")
  stdout.flushFile()

proc waitBeforeExit*() =
  # Keeps the window open when the app is double-clicked.
  echo ""
  stdout.write("Press ENTER to exit...")
  discard stdin.readLine()

