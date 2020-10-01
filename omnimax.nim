# MIT License
# 
# Copyright (c) 2020 Francesco Cameli
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import cligen, terminal, os, strutils, osproc

#the CMakeLists doesn't need to be re-evaluated at each loop
include "omnimaxpkg/Static/CMakeLists.txt.nim"

#Package version is passed as argument when building. It will be constant and set correctly
const 
    NimblePkgVersion {.strdefine.} = ""
    omnimax_ver = NimblePkgVersion

#Default to the omni nimble folder, which should have it installed if omni has been installed correctly
const default_max_api_path = "~/.nimble/pkgs/omnimax-" & omnimax_ver & "/omnimaxpkg/deps/max-api"

#Extension for static lib
const static_lib_extension = ".a"

when defined(Windows):
    const max_object_extension = ".mxe64"
else:
    const max_object_extension = ".mxo"

#It's the same in MacOS and Windows
const default_packages_path = "~/Documents/Max 8/Packages"

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

proc omnimax_single_file(fileFullPath : string, mc : bool = true, architecture : string = "native", outDir : string = default_packages_path, maxPath : string = default_max_api_path, removeBuildFiles : bool = true) : int =

    var 
        omniFile     = splitFile(fileFullPath)
        omniFileDir  = omniFile.dir
        omniFileName = omniFile.name
        omniFileExt  = omniFile.ext

    let originalOmniFileName = omniFileName

    #Check file first charcter, must be a capital letter
    if not omniFileName[0].isUpperAscii:
        omniFileName[0] = omniFileName[0].toUpperAscii()

    #Check file extension
    if not(omniFileExt == ".omni") and not(omniFileExt == ".oi"):
        printError($fileFullPath & " is not an omni file.")
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
    
    let 
        omni_max_object_name = omniFileName.toLowerAscii()
        omni_max_object_name_tilde = omni_max_object_name & "_tilde"
        omni_max_object_name_tilde_symbol = omni_max_object_name & "~"

    #Full paths to the new file in omniFileName directory
    let 
        #New folder named with the name of the Omni file
        fullPathToNewFolder = $omniFileDir & "/" & $omni_max_object_name_tilde

        #This is the Omni file copied to the new folder
        fullPathToOmniFile   = $fullPathToNewFolder & "/" & $omniFileName & $omniFileExt

        #These are the .cpp, .sc and cmake files in new folder
        fullPathToCppFile   = $fullPathToNewFolder & "/" & $omni_max_object_name_tilde & ".cpp"
        fullPathToCMakeFile = $fullPathToNewFolder & "/" & "CMakeLists.txt"

        #These are the paths to the generated static libraries
        fullPathToStaticLib = $fullPathToNewFolder & "/lib" & $omniFileName & $static_lib_extension
    
    #Create directory in same folder as .omni file
    removeDir(fullPathToNewFolder)
    createDir(fullPathToNewFolder)

    #Copy omniFile to folder
    copyFile(fileFullPath, fullPathToOmniFile)

    # ================ #
    # COMPILE NIM FILE #
    # ================ #

    #Compile nim file. Only pass the -d:writeIO and -d:tempDir flag here, so it generates the IO.txt file.
    let omni_command = "omni \"" & $fileFullPath & "\" -a:" & $architecture & " -i:omnimax_lang -b:64 -l:static -d:multithreadBuffers -d:writeIO -d:tempDir:\"" & $fullPathToNewFolder & "\" -o:\"" & $fullPathToNewFolder & "\""

    #Windows requires powershell to figure out the .nimble path... go figure!
    when not defined(Windows):
        let failedOmniCompilation = execCmd(omni_command)
    else:
        let failedOmniCompilation = execShellCmd(omni_command)

    #error code from execCmd is usually some 8bit number saying what error arises. I don't care which one for now.
    if failedOmniCompilation > 0:
        printError("Unsuccessful compilation of " & $originalOmniFileName & $omniFileExt & ".")
        removeDir(fullPathToNewFolder)
        return 1
    
    # ================ #
    #  RETRIEVE I / O  #
    # ================ #
    
    let 
        fullPathToIOFile = fullPathToNewFolder & "/IO.txt"
        io_file = readFile(fullPathToIOFile)
        io_file_seq = io_file.split('\n')

    if io_file_seq.len != 5:
        printError("Invalid IO.txt file.")
        removeDir(fullPathToNewFolder)
        return 1
    
    let 
        num_inputs  = parseInt(io_file_seq[0])
        input_names_string = io_file_seq[1]
        input_names = input_names_string.split(',') #this is a seq now
        default_vals_string = io_file_seq[2]
        default_vals = default_vals_string.split(',')
        num_outputs = parseInt(io_file_seq[3])
        output_names_string = io_file_seq[4]
        output_names = output_names_string.split(',') #this is a seq now

    # ======= #
    # SET I/O #
    # ======= #

    var 
        define_obj_name    = "#define OBJ_NAME \"" & $omni_max_object_name_tilde_symbol & "\""
        define_num_ins     = "#define NUM_INS " & $num_inputs
        const_inlet_names  = "const std::array<std::string," & $num_inputs & "> inlet_names = { "
        const_default_vals = "const std::array<double, " & $num_inputs & "> default_vals = { " 
        define_num_outs    = "#define NUM_OUTS " & $num_outputs
        const_outlet_names = "const std::array<std::string," & $num_outputs & "> outlet_names = { "

    #No input names
    if input_names[0] == "__NO_PARAM_NAMES__":
        if num_inputs == 0:
            const_inlet_names.add("};")
            const_default_vals.add("};")
        else:
            for i in 1..num_inputs:
                let default_val = default_vals[(i - 1)]
                if i == num_inputs:
                    const_inlet_names.add("\"in" & $i & "\" };")
                    const_default_vals.add($default_val & " };")
                else:
                    const_inlet_names.add("\"in" & $i & "\", ")
                    const_default_vals.add($default_val & ", ")
    else:
        if num_inputs == 0:
            const_inlet_names.add("};")
            const_default_vals.add("};")
        else:
            for index, input_name in input_names:
                let default_val = default_vals[index]
                if index == num_inputs - 1:
                    const_inlet_names.add("\"" & $input_name & "\" };")
                    const_default_vals.add($default_val & " };")
                else:
                    const_inlet_names.add("\"" & $input_name & "\", ")
                    const_default_vals.add($default_val & ", ")

    #No output names
    if output_names[0] == "__NO_PARAM_NAMES__":
        if num_outputs == 0:
            const_outlet_names.add("};")
        else:
            for i in 1..num_outputs:
                if i == num_outputs:
                    const_outlet_names.add("\"out" & $i & "\" };")
                else:
                    const_outlet_names.add("\"out" & $i & "\", ")
    else:
        if num_outputs == 0:
            const_outlet_names.add("};")
        else:
            for index, output_name in output_names:
                if index == num_outputs - 1:
                    const_outlet_names.add("\"" & $output_name & "\" };")
                else:
                    const_outlet_names.add("\"" & $output_name & "\", ")

    #This is the cpp file to overwrite! Need it at every iteration
    include "omnimaxpkg/Static/Omni_PROTO.cpp.nim"
    
    #Reconstruct the cpp file
    OMNI_PROTO_CPP = $OMNI_PROTO_INCLUDES & $define_obj_name & "\n" & $define_num_ins & "\n" & $define_num_outs & "\n" & $const_inlet_names & "\n" & const_default_vals & "\n" & $const_outlet_names & "\n" & $OMNI_PROTO_CPP
    
    # =========== #
    # WRITE FILES #
    # =========== #

    let
        cppFile   = open(fullPathToCppFile, fmWrite)
        cmakeFile = open(fullPathToCMakeFile, fmWrite)

    cppFile.write(OMNI_PROTO_CPP)
    cmakeFile.write(OMNI_PROTO_CMAKE)

    cppFile.close
    cmakeFile.close

    # ============ #
    # BUILD object #
    # ============ #

    #Create build folder
    removeDir($fullPathToNewFolder & "/build")
    createDir($fullPathToNewFolder & "/build")

    var cmake_cmd : string

    when(not(defined(Windows))):
        cmake_cmd = "cmake -DOMNI_BUILD_DIR=\"" & $fullPathToNewFolder & "\" -DOMNI_LIB_NAME=\"" & $omni_file_name & "\" -DC74_MAX_API_DIR=\"" & $expanded_max_path & "\" -DCMAKE_BUILD_TYPE=Release -DBUILD_MARCH=" & $architecture & " .."
    else:
        #Cmake wants a path in unix style, not windows! Replace "/" with "\"
        let fullPathToNewFolder_Unix = fullPathToNewFolder.replace("\\", "/")
        let fullPathToMaxApi_Unix = expanded_max_path.replace("\\", "/")
        
        cmake_cmd = "cmake -G \"MinGW Makefiles\" -DOMNI_BUILD_DIR=\"" & $fullPathToNewFolder_Unix & "\" -DOMNI_LIB_NAME=\"" & $omni_file_name & "\" -DC74_MAX_API_DIR=\"" & $fullPathToMaxApi_Unix & "\" -DCMAKE_BUILD_TYPE=Release -DBUILD_MARCH=" & $architecture & " .."

    #cd into the build directory
    setCurrentDir(fullPathToNewFolder & "/build")
    
    #Execute CMake
    when not defined(Windows):
        let failedCmake = execCmd(cmake_cmd)
    else:
        let failedCmake = execShellCmd(cmake_cmd)

    #error code from execCmd is usually some 8bit number saying what error arises. I don't care which one for now.
    if failedCmake > 0:
        printError("Unsuccessful cmake generation of the object file \"" & $omni_max_object_name_tilde & ".cpp\".")
        removeDir(fullPathToNewFolder)
        return 1
    
    #make command
    when not(defined(Windows)):
        let 
            compilation_cmd = "make"
            #compilation_cmd = "cmake --build . --config Release"
            failedCompilation = execCmd(compilation_cmd)
    else:
        let 
            compilation_cmd  = "mingw32-make"
            #compilation_cmd = "cmake --build . --config Release"
            failedCompilation = execShellCmd(compilation_cmd)

    if failedCompilation > 0:
        printError("Unsuccessful compilation the object file \"" & $omni_max_object_name_tilde & ".cpp\".")
        removeDir(fullPathToNewFolder)
        return 1
    
    let 
        external_name_and_extension = $omni_max_object_name_tilde_symbol & $max_object_extension
        fullPathToBuiltExternal = $fullPathToNewFolder & "/" & $external_name_and_extension

    #On windows, the external is getting called lib... strip lib from the name
    when defined(Windows):
        moveFile($fullPathToNewFolder & "/lib" & $omni_max_object_name_tilde_symbol & $max_object_extension, fullPathToBuiltExternal)

    #cd back to the original folder where omni file is
    setCurrentDir(omniFileDir)
    
    # ============== #
    # CREATE MC FILE #
    # ============== #
    
    var fullPathToMCFile : string
    
    if(mc):
        fullPathToMCFile = $fullPathToNewFolder & "/" & $omni_max_object_name_tilde & ".txt"
        writeFile(fullPathToMCFile, "max objectfile mc." & $omni_max_object_name_tilde_symbol & " mc.wrapper~ " & $omni_max_object_name_tilde_symbol)

    # ======================= #
    # COPY TO PACKAGES FOLDER #
    # ======================= #

    #Remove build dir
    removeDir(fullPathToNewFolder & "/build")

    #Remove tmp dir
    when defined(Windows):
        removeDir(fullPathToNewFolder & "/tmp")

    #Create externals dir and move the external over there
    let 
        fullPathToExternalsDir  = fullPathToNewFolder & "/externals"
        fullPathToMovedExternal = fullPathToNewFolder & "/externals/" & $external_name_and_extension
    createDir(fullPathToExternalsDir)
    moveFile(fullPathToBuiltExternal, fullPathToMovedExternal)
    
    #Create init dir and copy the mc txt file
    if(mc):
        let 
            fullPathToInitDir     = fullPathToNewFolder & "/init"
            fullPathToMovedMCFile = fullPathToInitDir & "/" & $omni_max_object_name_tilde_symbol & ".txt"
        createDir(fullPathToInitDir)
        moveFile(fullPathToMCFile, fullPathToMovedMCFile)

    #If removeBuildFiles, remove all sources and static libraries compiled
    if removeBuildFiles:
        let fullPathToOmniHeaderFile = fullPathToNewFolder & "/omni.h"
        removeFile(fullPathToOmniHeaderFile)
        removeFile(fullPathToCppFile)
        removeFile(fullPathToOmniFile)
        removeFile(fullPathToCMakeFile)
        removeFile(fullPathToIOFile)
        removeFile(fullPathToStaticLib)
    
    #Or, create a src dir and move them all there
    else:
        let fullPathToSrcDir = fullPathToNewFolder & "/src"
        createDir(fullPathToSrcDir)

        let fullPathToOmniHeaderFile = fullPathToNewFolder & "/omni.h"
        moveFile(fullPathToOmniHeaderFile, fullPathToSrcDir & "/omni.h")
        moveFile(fullPathToCppFile, fullPathToSrcDir & "/" & $omni_max_object_name_tilde & ".cpp")
        moveFile(fullPathToOmniFile, fullPathToSrcDir & "/" & $omniFileName & $omniFileExt)
        moveFile(fullPathToCMakeFile, fullPathToSrcDir & "/CMakeLists.txt")
        moveFile(fullPathToIOFile, fullPathToSrcDir & "/IO.txt")
        moveFile(fullPathToStaticLib, fullPathToSrcDir & "/lib" & $omni_file_name & $static_lib_extension)

    #Copy to extensions folder
    let 
        fullPathToOutDir_tilde = $expanded_out_dir & "/" & $omni_max_object_name_tilde #omnisaw_tilde
        fullPathToOutDir = $expanded_out_dir & "/" & $omni_file_name #OmniSaw
    
    #Remove temp folder used for compilation only if it differs from outDir (otherwise, it's gonna delete the actual folder)
    if fullPathToOutDir_tilde != fullPathToNewFolder:
        #Remove previous folders if there were
        removeDir(fullPathToOutDir_tilde)
        removeDir(fullPathToOutDir)
        
        #Copy new one
        copyDir(fullPathToNewFolder, fullPathToOutDir_tilde)

        #Rename the folder to omni_name (instead of omni_name_tilde)
        moveDir(fullPathToOutDir_tilde, fullPathToOutDir)

        #Remove temp folder used for compilation
        removeDir(fullPathToNewFolder)

    printDone("The " & $omni_max_object_name_tilde_symbol & " object has been correctly built and installed in \"" & $expanded_out_dir & "\".")

    return 0

proc omnimax(omniFiles : seq[string], mc : bool = true, architecture : string = "native", outDir : string = default_packages_path, maxPath : string = default_max_api_path, removeBuildFiles : bool = true) : int =
    for omniFile in omniFiles:
        #Get full extended path
        let omniFileFullPath = omniFile.normalizedPath().expandTilde().absolutePath()

        #If it's a file, compile it
        if omniFileFullPath.existsFile():
            if omnimax_single_file(omniFileFullPath, mc, architecture, outDir, maxPath, removeBuildFiles) > 0:
                return 1

        #If it's a dir, compile all .omni/.oi files in it
        elif omniFileFullPath.existsDir():
            for kind, dirFile in walkDir(omniFileFullPath):
                if kind == pcFile:
                    let 
                        dirFileFullPath = dirFile.normalizedPath().expandTilde().absolutePath()
                        dirFileExt = dirFileFullPath.splitFile().ext
                    
                    if dirFileExt == ".omni" or dirFileExt == ".oi":
                        if omnimax_single_file(dirFileFullPath, mc, architecture, outDir, maxPath, removeBuildFiles) > 0:
                            return 1

        else:
            printError($omniFileFullPath & " does not exist.")
            return 1
    
    return 0

#Dispatch the omnimax function as the CLI one
dispatch(omnimax, 
    short={
        "mc" : 'm',
        "maxPath" : 'p'
    }, 

    help={ 
        "mc" : "Build with mc support.",
        "architecture" : "Build architecture.",
        "outDir" : "Output directory. Defaults to the Max 8 Packages' path.",
        "maxPath" : "Path to the max-api folder. Defaults to the one in omnimax's dependencies.", 
        "removeBuildFiles" : "Remove source files used for compilation from outDir."        
    }
)
