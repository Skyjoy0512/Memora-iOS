-- Development validation of synthetic fixtures only, never a user's template.
on run arguments
  if (count arguments) is not 2 then error "Pass input PPTX and new output PDF paths"
  set inputFile to POSIX file (item 1 of arguments) as alias
  set outputFile to POSIX file (item 2 of arguments)
  with timeout of 55 seconds
    tell application id "com.apple.Keynote"
      set fixture to open inputFile
      try
        export fixture to outputFile as PDF
      on error errorText number errorNumber
        close fixture saving no
        error errorText number errorNumber
      end try
      close fixture saving no
      return version
    end tell
  end timeout
end run
