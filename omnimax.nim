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
    writeStyled("ERROR: ", {styleBright}) 
    setForegroundColor(fgWhite, true)
    writeStyled(msg & "\n")

proc printDone(msg : string) : void =
    setForegroundColor(fgGreen)
    writeStyled("DONE: ", {styleBright}) 
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