import cligen, terminal, os, strutils, osproc

#Package version is passed as argument when building. It will be constant and set correctly
const 
    NimblePkgVersion {.strdefine.} = ""
    omnimax_ver = NimblePkgVersion

#Extension for static lib
const static_lib_extension = ".a"

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

proc omnimax(omniFile : string, supernova : bool = false, architecture : string = "native", outDir : string = "", maxPath : string = "", removeBuildFiles : bool = true) : int =

    let 
        fullPathToFile = omniFile.normalizedPath().expandTilde().absolutePath()
        
        #This is the path to the original nim file to be used in shell.
        #Using this one in nim command so that errors are shown on this one when CTRL+Click on terminal
        #fullPathToOriginalOmniFileShell = fullPathToFile.replace(" ", "\\ ")

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

proc omnimax_cli(omniFiles : seq[string], supernova : bool = false, architecture : string = "native", outDir : string = "", maxPath : string = "", removeBuildFiles : bool = true) : int =
    return 0

#Dispatch the omnimax function as the CLI one
dispatch(omnimax_cli, 
    short={}, 
    
    help={ 
      
    }

)