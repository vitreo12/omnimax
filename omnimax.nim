# MIT License
# 
# Copyright (c) 2020-2021 Francesco Cameli
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

import cligen, terminal, os, strutils

when not defined(Windows):
    import osproc

#the CMakeLists doesn't need to be re-evaluated at each loop
include "omnimaxpkg/Static/CMakeLists.txt.nim"

#Package version is passed as argument when building. It will be constant and set correctly
const 
    NimblePkgVersion {.strdefine.} = ""
    omnimax_ver = NimblePkgVersion

#-v / --version
let version_flag = "OmniMax - version " & $omnimax_ver & "\n(c) 2020-2021 Francesco Cameli"

#Default to the omni nimble folder, which should have it installed if omnimax has been installed correctly
const default_max_api_path = "~/.nimble/pkgs/omnimax-" & omnimax_ver & "/omnimaxpkg/deps/max-api"

#Extension for static lib
when defined(Windows):
    const static_lib_extension = ".lib"
else:
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

proc omnimax_single_file(fileFullPath : string, outDir : string = "", maxPath : string = "", architecture : string = "native", mc : bool = true, removeBuildFiles : bool = true) : int =
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
        printError($fileFullPath & " is not an Omni file.")
        return 1

    var expanded_max_path : string
    
    if maxPath == "":
        expanded_max_path = default_max_api_path
    else:
        expanded_max_path = maxPath

    expanded_max_path = expanded_max_path.normalizedPath().expandTilde().absolutePath()

    #Check maxPath
    if not expanded_max_path.dirExists():
        printError("maxPath: " & $expanded_max_path & " does not exist.")
        return 1
    
    var expanded_out_dir : string

    if expanded_out_dir == "":
        expanded_out_dir = default_packages_path
    else:
        expanded_out_dir = outDir

    expanded_out_dir = expanded_out_dir.normalizedPath().expandTilde().absolutePath()

    #Check outDir
    if not expanded_out_dir.dirExists():
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

    #Compile nim file. 
    let omni_command = "omni \"" & $fileFullPath & "\" --architecture:" & $architecture & " --lib:static --wrapper:omnimax_lang --performBits:64 --exportIO:true --outDir:\"" & $fullPathToNewFolder & "\""

    #Windows requires powershell to figure out the .nimble path...
    when defined(Windows):
        let failedOmniCompilation = execShellCmd(omni_command)
    else:
        let failedOmniCompilation = execCmd(omni_command)

    #error code from execCmd is usually some 8bit number saying what error arises. I don't care which one for now.
    if failedOmniCompilation > 0:
        printError("Unsuccessful compilation of " & $originalOmniFileName & $omniFileExt & ".")
        removeDir(fullPathToNewFolder)
        return 1
    
    # ================ #
    #  RETRIEVE I / O  #
    # ================ #
    
    let 
        fullPathToIOFile = fullPathToNewFolder & "/omni_io.txt"
        io_file = readFile(fullPathToIOFile)
        io_file_seq = io_file.split('\n')

    if io_file_seq.len != 11:
        printError("Invalid omni_io.txt file.")
        removeDir(fullPathToNewFolder)
        return 1
    
    let 
        num_inputs = parseInt(io_file_seq[0])     
        inputs_names_string = io_file_seq[1]
        inputs_names = inputs_names_string.split(',')
        inputs_defaults_string = io_file_seq[2]
        inputs_defaults = inputs_defaults_string.split(',')
        num_params = parseInt(io_file_seq[3])
        params_names_string = io_file_seq[4]
        params_names = params_names_string.split(',')
        params_defaults_string = io_file_seq[5]
        params_defaults = params_defaults_string.split(',')
        num_buffers = parseInt(io_file_seq[6])
        buffers_names_string = io_file_seq[7]
        buffers_names = buffers_names_string.split(',')
        buffers_defaults_string = io_file_seq[8]
        buffers_defaults = buffers_defaults_string.split(',')
        num_outputs = parseInt(io_file_seq[9])
        outputs_names_string = io_file_seq[10]
        outputs_names = outputs_names_string.split(',')

    # ======= #
    # SET I/O #
    # ======= #

    var 
        define_obj_name        = "#define OBJ_NAME \"" & $omni_max_object_name_tilde_symbol & "\""
        define_num_ins         = "#define NUM_INS " & $num_inputs
        define_num_params      = "#define NUM_PARAMS " & $num_params
        define_num_buffers     = "#define NUM_BUFFERS " & $num_buffers
        define_num_outs        = "#define NUM_OUTS " & $num_outputs
        const_inputs_names     = "const std::array<std::string,NUM_INS> inputs_names = { "
        const_inputs_defaults  = "const std::array<double,NUM_INS> inputs_defaults = { " 
        const_params_names     = "const std::array<std::string,NUM_PARAMS> params_names = { "
        const_params_defaults  = "const std::array<double,NUM_PARAMS> params_defaults = { " 
        const_buffers_names    = "const std::array<std::string,NUM_BUFFERS> buffers_names = { "
        const_buffers_defaults = "const std::array<std::string,NUM_BUFFERS> buffers_defaults = { "
        const_outputs_names    = "const std::array<std::string,NUM_OUTS> outputs_names = { "

    if num_inputs == 0:
        const_inputs_names.add("};")
        const_inputs_defaults.add("};")
    else:
        for index, input_name in inputs_names:
            let default_val = inputs_defaults[index]
            if index == num_inputs - 1:
                const_inputs_names.add("\"" & $input_name & "\" };")
                const_inputs_defaults.add($default_val & " };")
            else:
                const_inputs_names.add("\"" & $input_name & "\", ")
                const_inputs_defaults.add($default_val & ", ")

    if num_params == 0:
        const_params_names.add("};")
        const_params_defaults.add("};")
    else:
        for index, param_name in params_names:
            let default_val = params_defaults[index]
            if index == num_params - 1:
                const_params_names.add("\"" & $param_name & "\" };")
                const_params_defaults.add($default_val & " };")
            else:
                const_params_names.add("\"" & $param_name & "\", ")
                const_params_defaults.add($default_val & ", ")

    if num_buffers == 0:
        const_buffers_names.add("};")
        const_buffers_defaults.add("};")
    else:
        for index, buffer_name in buffers_names:
            let default_val = buffers_defaults[index]
            if index == num_buffers - 1:
                const_buffers_names.add("\"" & $buffer_name & "\" };")
                const_buffers_defaults.add("\"" & $default_val & "\" };")
            else:
                const_buffers_names.add("\"" & $buffer_name & "\", ")
                const_buffers_defaults.add("\"" & $default_val & "\", ")

    if num_outputs == 0:
        const_outputs_names.add("};")
    else:
        for index, output_name in outputs_names:
            if index == num_outputs - 1:
                const_outputs_names.add("\"" & $output_name & "\" };")
            else:
                const_outputs_names.add("\"" & $output_name & "\", ")

    #This is the cpp file to overwrite! Need it at every iteration
    include "omnimaxpkg/Static/Omni_PROTO.cpp.nim"
    
    #Reconstruct the cpp file
    OMNI_PROTO_CPP = (
        $OMNI_PROTO_INCLUDES & 
        $define_obj_name & "\n" & 
        $define_num_ins & "\n" & 
        $define_num_params & "\n" & 
        $define_num_buffers & "\n" & 
        $define_num_outs & "\n" & 
        $const_inputs_names & "\n" & 
        $const_inputs_defaults & "\n" & 
        $const_params_names & "\n" & 
        $const_params_defaults & "\n" & 
        $const_buffers_names & "\n" & 
        $const_buffers_defaults & "\n" & 
        $const_outputs_names & "\n" & 
        $OMNI_PROTO_CPP
    )

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

    when defined(Windows):
        #Cmake wants a path in unix style, not windows! Replace "/" with "\"
        let fullPathToNewFolder_Unix = fullPathToNewFolder.replace("\\", "/")
        let fullPathToMaxApi_Unix = expanded_max_path.replace("\\", "/")
        cmake_cmd = "cmake -G \"MinGW Makefiles\" -DOMNI_BUILD_DIR=\"" & $fullPathToNewFolder_Unix & "\" -DOMNI_LIB_NAME=\"" & $omni_file_name & "\" -DC74_MAX_API_DIR=\"" & $fullPathToMaxApi_Unix & "\" -DCMAKE_BUILD_TYPE=Release -DBUILD_MARCH=" & $architecture & " .."
    else:
        cmake_cmd = "cmake -DOMNI_BUILD_DIR=\"" & $fullPathToNewFolder & "\" -DOMNI_LIB_NAME=\"" & $omni_file_name & "\" -DC74_MAX_API_DIR=\"" & $expanded_max_path & "\" -DCMAKE_BUILD_TYPE=Release -DBUILD_MARCH=" & $architecture & " .."

    #cd into the build directory
    setCurrentDir(fullPathToNewFolder & "/build")
    
    #Execute CMake
    when defined(Windows):
        let failedCmake = execShellCmd(cmake_cmd)
    else:
        let failedCmake = execCmd(cmake_cmd)

    #error code from execCmd is usually some 8bit number saying what error arises. I don't care which one for now.
    if failedCmake > 0:
        printError("Unsuccessful cmake generation of the object file \"" & $omni_max_object_name_tilde & ".cpp\".")
        removeDir(fullPathToNewFolder)
        return 1
    
    #make command
    when defined(Windows):
        let 
            compilation_cmd  = "mingw32-make"
            #compilation_cmd = "cmake --build . --config Release"
            failedCompilation = execShellCmd(compilation_cmd)
    else:
        let 
            compilation_cmd = "make"
            #compilation_cmd = "cmake --build . --config Release"
            failedCompilation = execCmd(compilation_cmd)

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
        let 
            fullPathToSrcDir = fullPathToNewFolder & "/src"
            fullPathToOmniHeaderFile = fullPathToNewFolder & "/omni.h"
        createDir(fullPathToSrcDir)
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

proc omnimax(files : seq[string], outDir : string = "", maxPath : string = "", architecture : string = "native", mc : bool = true, removeBuildFiles : bool = true) : int =
    #no files provided, print --version
    if files.len == 0:
        echo version_flag
        return 0

    for omniFile in files:
        #Get full extended path
        let omniFileFullPath = omniFile.normalizedPath().expandTilde().absolutePath()

        #If it's a file, compile it
        if omniFileFullPath.fileExists():
            if omnimax_single_file(omniFileFullPath, outDir, maxPath, architecture, mc, removeBuildFiles) > 0:
                return 1

        #If it's a dir, compile all .omni/.oi files in it
        elif omniFileFullPath.dirExists():
            for kind, dirFile in walkDir(omniFileFullPath):
                if kind == pcFile:
                    let 
                        dirFileFullPath = dirFile.normalizedPath().expandTilde().absolutePath()
                        dirFileExt = dirFileFullPath.splitFile().ext
                    
                    if dirFileExt == ".omni" or dirFileExt == ".oi":
                        if omnimax_single_file(dirFileFullPath, outDir, maxPath, architecture, mc, removeBuildFiles) > 0:
                            return 1

        else:
            printError($omniFileFullPath & " does not exist.")
            return 1

    return 0

#Workaround to pass custom version
clCfg.version = version_flag

#Remove --help-syntax
clCfg.helpSyntax = ""

#Arguments string
let arguments = "Arguments:\n  Omni file(s) or folder."

#Ignore clValType
clCfg.hTabCols = @[ clOptKeys, #[clValType,]# clDflVal, clDescrip ]

#Dispatch the omnimax function as the CLI one
dispatch(
    omnimax, 
    
    #Remove "Usage: ..."
    noHdr = true,
    
    #Custom options printing
    usage = version_flag & "\n\n" & arguments & "\n\nOptions:\n$options",
    
    short = {
        "version" : 'v',
        "mc" : 'm',
        "maxPath" : 'p'
    }, 

    help = { 
        "help" : "CLIGEN-NOHELP",
        "version" : "CLIGEN-NOHELP",
        "outDir" : "Output directory. Defaults to the Max 8 Packages' path: \"" & $default_packages_path & "\".",
        "maxPath" : "Path to the max-api folder. Defaults to the one in OmniMax's dependencies: \"" & $default_max_api_path & ".\"" ,
        "architecture" : "Build architecture.",
        "mc" : "Build with mc support.",
        "removeBuildFiles" : "Remove source files used for compilation from outDir."        
    }
)
