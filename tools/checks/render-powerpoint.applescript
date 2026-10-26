-- Opens only the supplied synthetic fixture, leaving other presentations alone.
-- osascript tools/checks/render-powerpoint.applescript /absolute/input.pptx /absolute/output.pdf
on run arguments
  if (count arguments) is not 2 then error "Pass input PPTX and output PDF paths"
  set inputFile to POSIX file (item 1 of arguments) as alias
  set outputFile to POSIX file (item 2 of arguments)
  with timeout of 55 seconds
    tell application id "com.microsoft.Powerpoint"
      open inputFile
      set fixture to active presentation
      try
        save fixture in outputFile as save as PDF
      on error errorText number errorNumber
        close fixture saving no
        error errorText number errorNumber
      end try
      close fixture saving no
      return version
    end tell
  end timeout
end run
