import cligen, terminal, os, strutils, osproc

#Package version is passed as argument when building. It will be constant and set correctly
const 
    NimblePkgVersion {.strdefine.} = ""
    omnimax_ver = NimblePkgVersion

#Default to the omni nimble folder, which should have it installed if omni has been installed correctly
const default_max_api_path = "~/.nimble/pkgs/omnimax-" & omnimax_ver & "/omnimaxpkg/deps/max-api"

#Extension for static lib
const static_lib_extension = ".a"

#It's the same in MacOS and Windows
const default_library_path = "~/Documents/Max 8/Library"

proc printError(msg : string) : void =
    setForegroundColor(fgRed)
    writeStyled("ERROR [omnimax]: ", {styleBright}) 
    setForegroundColor(fgWhite, true)
    writeStyled(msg & "\n")

proc printDone(msg : string) : void =
    setForegroundColor(fgGreen)
    writeStyled("DONE [omnimax]: ", {styleBright}) 
    setForegroundColor(fgWhite, true)
    writeStyled(msg & "\n")

proc omnimax_single_file(omniFile : string, mc : bool = false, architecture : string = "native", outDir : string = default_library_path, maxPath : string = default_max_api_path, removeBuildFiles : bool = true) : int =

    let fullPathToFile = omniFile.normalizedPath().expandTilde().absolutePath()

    #Check if file exists
    if not fullPathToFile.existsFile():
        printError($fullPathToFile & " doesn't exist.")
        return 1
    
    var 
        omniFile     = splitFile(fullPathToFile)
        omniFileDir  = omniFile.dir
        omniFileName = omniFile.name
        omniFileExt  = omniFile.ext

    #Check file first charcter, must be a capital letter
    if not omniFileName[0].isUpperAscii:
        omniFileName[0] = omniFileName[0].toUpperAscii()

    #Check file extension
    if not(omniFileExt == ".omni") and not(omniFileExt == ".oi"):
        printError($fullPathToFile & " is not an omni file.")
        return 1

    let expanded_max_path = maxPath.normalizedPath().expandTilde().absolutePath()

    #Check maxPath
    if not expanded_max_path.existsDir():
        printError("maxPath: " & $expanded_max_path & " does not exist.")
        return 1
    
    let expanded_out_dir = outDir.normalizedPath().expandTilde().absolutePath()

    #Check outDir
    if not expanded_out_dir.existsDir():
        printError("outDir: " & $expanded_out_dir & " does not exist.")
        return 1

    #Full paths to the new file in omniFileName directory
    let 
        #New folder named with the name of the Omni file
        fullPathToNewFolder = $omniFileDir & "/" & $omniFileName

        #This is the Omni file copied to the new folder
        fullPathToOmniFile   = $fullPathToNewFolder & "/" & $omniFileName & $omniFileExt

        #These are the .cpp, .sc and cmake files in new folder
        fullPathToCppFile   = $fullPathToNewFolder & "/" & $omniFileName & ".cpp"
        fullPathToCMakeFile = $fullPathToNewFolder & "/" & "CMakeLists.txt"

        #These are the paths to the generated static libraries
        fullPathToStaticLib = $fullPathToNewFolder & "/lib" & $omniFileName & $static_lib_extension
    
    #Create directory in same folder as .omni file
    removeDir(fullPathToNewFolder)
    createDir(fullPathToNewFolder)

    #Copy omniFile to folder
    copyFile(fullPathToFile, fullPathToOmniFile)

    # ================ #
    # COMPILE NIM FILE #
    # ================ #

    #Compile nim file. Only pass the -d:omnicli and -d:tempDir flag here, so it generates the IO.txt file.
    let omni_command = "omni \"" & $fullPathToFile & "\" -i:omnimax_lang -b:64 -u:false -l:static -d:writeIO -d:tempDir:\"" & $fullPathToNewFolder & "\" -o:\"" & $fullPathToNewFolder & "\""

    #Windows requires powershell to figure out the .nimble path... go figure!
    when not defined(Windows):
        let failedOmniCompilation = execCmd(omni_command)
    else:
        let failedOmniCompilation = execShellCmd(omni_command)

    #error code from execCmd is usually some 8bit number saying what error arises. I don't care which one for now.
    if failedOmniCompilation > 0:
        printError("Unsuccessful compilation of " & $omniFileName & $omniFileExt & ".")
        return 1
    
    #Also for mc
    if mc:
        discard

    return 0

proc omnimax(omniFiles : seq[string], mc : bool = false, architecture : string = "native", outDir : string = default_library_path, maxPath : string = default_max_api_path, removeBuildFiles : bool = true) : int =
    for omniFile in omniFiles:
        if omnimax_single_file(omniFile, mc, architecture, outDir, maxPath, removeBuildFiles) > 0:
            return 1
    
    return 0

#Dispatch the omnimax function as the CLI one
dispatch(omnimax, 
    short={
        "maxPath" : 'p',
        "mc" : 'm'
    }, 

    help={ 
        "mc" : "Build with mc support.",
        "architecture" : "Build architecture.",
        "outDir" : "Output directory. Defaults to Max's Library path.",
        "maxPath" : "Path to the max-api folder. Defaults to the one in omnimax's dependencies.", 
        "removeBuildFiles" : "Remove source files used for compilation from outDir."        
    }
)